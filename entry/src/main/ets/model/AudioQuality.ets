// 音质档位与音轨模型（audio-quality-settings）：
// QualityTier 四档枚举（数值即 B 站 qn 码）+ AudioTrack 音轨模型 + 档位映射/标签纯静态工具。
// 被 service（BiliService/PlayerController）与 pages（SettingsPage/PlayerOverlay）双侧引用，
// 独立成 model 文件避免 service↔pages 反向依赖；静态方法不使用 this。

export enum QualityTier {
  MAX = 0,      // 最高：取最高可用档，含 Hi-Res/杜比升级（无固定 qn）
  QHIRES = 30251, // Hi-Res 无损（大会员）
  QDOLBY = 30250, // 杜比全景声（大会员）
  Q192K = 30280,
  Q132K = 30232,
  Q64K = 30216
}

// playurl DASH 响应中的单条音轨：id 为 B 站档位码（flac/dolby 解析时补 30251/30250，durl 兜底为 0）
@ObservedV2
export class AudioTrack {
  @Trace id: number;
  @Trace bandwidth: number;
  @Trace urls: string[];

  constructor(id: number, bandwidth: number, urls: string[]) {
    this.id = id;
    this.bandwidth = bandwidth;
    this.urls = urls;
  }
}

// 服务端响度数据（v0.8-p5）：playurl 响应 data.volume 的严格类型载体（voice_balance=1 时下发，
// 实测见 BILI_NOTES §3.14）；随每次取流刷新，不缓存跨曲目
export class LoudnessData {
  // 播放器响度增益接口有效区间（media.AVPlayer.setLoudnessGain，dB）；
  // model 层禁止依赖 service（Constants 属 service），故边界常量在类内定义
  static readonly GAIN_MIN_DB: number = -90;
  static readonly GAIN_MAX_DB: number = 24;
  // 服务端实测综合响度（LUFS），核心字段
  measuredI: number;
  // 服务端实测真峰值（dBTP），缺失回退 0（保守假设峰值已满刻度，禁放大）
  measuredTp: number;
  // 目标响度（LUFS，实测恒 -14），核心字段
  targetI: number;
  // 可疑测量下限（dB，实测恒 -28），缺失回退 -Infinity（守卫惰性）
  undersizedTargetI: number;

  constructor(measuredI: number, measuredTp: number, targetI: number, undersizedTargetI: number) {
    this.measuredI = measuredI;
    this.measuredTp = measuredTp;
    this.targetI = targetI;
    this.undersizedTargetI = undersizedTargetI;
  }

  // 数值字段宽松读取：接受 JSON number / 数字字符串，非有限数值返回 NaN
  private static readFiniteNumber(raw: Object | undefined): number {
    if (raw === undefined || raw === null) {
      return NaN;
    }
    const n: number = Number(raw);
    return Number.isFinite(n) ? n : NaN;
  }

  // 解析 data.volume（v0.8-p5 FR-002）：volume 缺失或 measured_i/target_i 非有限数值 → undefined（无数据）；
  // undersized_target_i 自 multi_scene_args（值为字符串 map，BILI_NOTES §3.14）解析
  static parseVolume(raw: Object | undefined): LoudnessData | undefined {
    if (raw === undefined || raw === null) {
      return undefined;
    }
    const volume: Record<string, Object> = raw as Record<string, Object>;
    const measuredI: number = LoudnessData.readFiniteNumber(volume['measured_i']);
    const targetI: number = LoudnessData.readFiniteNumber(volume['target_i']);
    if (!Number.isFinite(measuredI) || !Number.isFinite(targetI)) {
      return undefined;
    }
    const measuredTpRaw: number = LoudnessData.readFiniteNumber(volume['measured_tp']);
    const measuredTp: number = Number.isFinite(measuredTpRaw) ? measuredTpRaw : 0;
    let undersizedTargetI: number = -Infinity;
    const argsRaw: Object | undefined = volume['multi_scene_args'];
    if (argsRaw !== undefined && argsRaw !== null) {
      const args: Record<string, Object> = argsRaw as Record<string, Object>;
      const underRaw: Object | undefined = args['undersized_target_i'];
      if (underRaw !== undefined && underRaw !== null) {
        const parsed: number = LoudnessData.readFiniteNumber(underRaw);
        if (Number.isFinite(parsed)) {
          undersizedTargetI = parsed;
        }
      }
    }
    return new LoudnessData(measuredI, measuredTp, targetI, undersizedTargetI);
  }

  // 增益计算（v0.8-p5 plan D3，官方 PC 同款公式）：gain = targetI − measuredI；
  // 守卫序：① measuredI < undersizedTargetI 可疑测量 → 0；② 防削波仅钳放大方向（gain>0 且越 0 dBFS
  // 时钳到 max(0, −measuredTp)，衰减永不限幅）；③ 接口区间钳制
  static computeGainDb(data: LoudnessData): number {
    if (data.measuredI < data.undersizedTargetI) {
      return 0;
    }
    let gain: number = data.targetI - data.measuredI;
    if (gain > 0 && data.measuredTp + gain > 0) {
      gain = Math.max(0, -data.measuredTp);
    }
    if (gain < LoudnessData.GAIN_MIN_DB) {
      return LoudnessData.GAIN_MIN_DB;
    }
    if (gain > LoudnessData.GAIN_MAX_DB) {
      return LoudnessData.GAIN_MAX_DB;
    }
    return gain;
  }
}

// resolveAudioTrack 的解析结果：id/urls 为选中音轨，tracks 为 dash 全量可用音轨（durl 兜底为空数组），
// source 标记来源（'dash' | 'durl'），供 playIndex/setQualityTier 记录音质状态；
// lastPlayTimeMs/lastPlayCid 为取流响应携带的云端播放进度（last_play_time 毫秒 / last_play_cid；
// 0=无/未登录/未返回），仅供 playIndex 新起播云端续播合并（lastPlayCid 严格匹配起播分P），换音质路径忽略；
// loudness 为服务端响度数据（v0.8-p5，无 volume 时 undefined）
export class ResolvedAudio {
  id: number;
  urls: string[];
  tracks: AudioTrack[];
  source: string;
  lastPlayTimeMs: number;
  lastPlayCid: number;
  loudness: LoudnessData | undefined = undefined;

  constructor(id: number, urls: string[], tracks: AudioTrack[], source: string,
    lastPlayTimeMs: number = 0, lastPlayCid: number = 0, loudness: LoudnessData | undefined = undefined) {
    this.id = id;
    this.urls = urls;
    this.tracks = tracks;
    this.source = source;
    this.lastPlayTimeMs = lastPlayTimeMs;
    this.lastPlayCid = lastPlayCid;
    this.loudness = loudness;
  }
}

export class AudioQuality {
  // 存储值归一（audio-quality-settings FR-001）：仅接受合法档位值，非法/未初始化（-1）回落 MAX
  static fromStored(n: number): QualityTier {
    if (n === QualityTier.QHIRES) {
      return QualityTier.QHIRES;
    }
    if (n === QualityTier.QDOLBY) {
      return QualityTier.QDOLBY;
    }
    if (n === QualityTier.Q192K) {
      return QualityTier.Q192K;
    }
    if (n === QualityTier.Q132K) {
      return QualityTier.Q132K;
    }
    if (n === QualityTier.Q64K) {
      return QualityTier.Q64K;
    }
    return QualityTier.MAX;
  }

  // 档位可用矩阵（v0.4-p1-2 FR-014）：64K 全员 / 132K 登录 / 192K·Hi-Res·杜比 大会员 / 最高语义档恒可选
  static availableTiers(isLogged: boolean, vipStatus: number): QualityTier[] {
    if (isLogged && vipStatus === 1) {
      return [QualityTier.MAX, QualityTier.QHIRES, QualityTier.QDOLBY, QualityTier.Q192K, QualityTier.Q132K, QualityTier.Q64K];
    }
    if (isLogged) {
      return [QualityTier.MAX, QualityTier.Q132K, QualityTier.Q64K];
    }
    return [QualityTier.MAX, QualityTier.Q64K];
  }

  // 已存档位收敛（v0.4-p1-2 US2 场景 4）：不可用档位逐级回落至下方最高可用档（Hi-Res/杜比→192K→132K→64K），
  // 仅显示层收敛不落盘
  static clampTier(tier: QualityTier, isLogged: boolean, vipStatus: number): QualityTier {
    if ((tier === QualityTier.QHIRES || tier === QualityTier.QDOLBY) && !(isLogged && vipStatus === 1)) {
      tier = QualityTier.Q192K;
    }
    if (tier === QualityTier.Q192K && !(isLogged && vipStatus === 1)) {
      tier = QualityTier.Q132K;
    }
    if (tier === QualityTier.Q132K && !isLogged) {
      tier = QualityTier.Q64K;
    }
    return tier;
  }

  // 档位显示名
  static label(tier: QualityTier): string {
    if (tier === QualityTier.QHIRES) {
      return 'Hi-Res';
    }
    if (tier === QualityTier.QDOLBY) {
      return '杜比';
    }
    if (tier === QualityTier.Q192K) {
      return '192K';
    }
    if (tier === QualityTier.Q132K) {
      return '132K';
    }
    if (tier === QualityTier.Q64K) {
      return '64K';
    }
    return '最高';
  }

  // 音轨码→档位写回映射（audio-quality-settings FR-004）：Hi-Res(30251)/杜比(30250) 仅能经「最高」档到达，写回 MAX
  static tierOfTrackId(id: number): QualityTier {
    if (id === QualityTier.Q192K) {
      return QualityTier.Q192K;
    }
    if (id === QualityTier.Q132K) {
      return QualityTier.Q132K;
    }
    if (id === QualityTier.Q64K) {
      return QualityTier.Q64K;
    }
    return QualityTier.MAX;
  }

  // 音轨码显示名（audio-quality-settings US3 面板列表）：未知码回落「默认」
  static trackLabel(id: number): string {
    if (id === 30251) {
      return 'Hi-Res';
    }
    if (id === 30250) {
      return '杜比';
    }
    if (id === QualityTier.Q192K) {
      return '192K';
    }
    if (id === QualityTier.Q132K) {
      return '132K';
    }
    if (id === QualityTier.Q64K) {
      return '64K';
    }
    return '默认';
  }
}
