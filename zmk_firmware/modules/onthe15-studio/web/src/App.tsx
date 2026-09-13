import { useContext, useEffect, useRef, useState } from "react";
import { connect as gattConnect } from "@zmkfirmware/zmk-studio-ts-client/transport/gatt";
import {
  connectSerial, isWebBluetoothSupported, isWebSerialSupported,
  ZMKAppContext, ZMKConnection, useCustomSubsystem,
} from "@cormoran/zmk-studio-react-hook";
import {
  BatteryChemistry, LightingEffect, PowerActivity, Request, Response, SelectedTransport,
  type BatterySettingsResponse, type GetFirmwareInfoResponse,
  type LightingEffectsResponse,
  type LightingSettings as LightingSettingsValue, type LightingSettingsResponse,
  type PowerDiagnostics,
  type StatusSettingsResponse,
} from "./proto/onthe15/studio/studio";

export const SUBSYSTEM_IDENTIFIER = "onthe15__studio";

function localizedError(reason: unknown, fallback: string): string {
  const message = reason instanceof Error ? reason.message : fallback;
  if (message === "Operation timed out") return "操作がタイムアウトしました";
  if (message.startsWith("Connection timed out")) return "接続がタイムアウトしました。デバイスが応答していません。";
  return message;
}

let rpcQueue: Promise<void> = Promise.resolve();

function enqueueRpc<T>(operation: () => Promise<T>): Promise<T> {
  const result = rpcQueue.then(operation, operation);
  rpcQueue = result.then(() => undefined, () => undefined);
  return result;
}

export function FirmwareInfo() {
  const app = useContext(ZMKAppContext);
  const { ready, subsystem, call } = useCustomSubsystem(SUBSYSTEM_IDENTIFIER, {
    encode: (request: Request) => Request.encode(request).finish(),
    decode: Response.decode,
  });
  const [info, setInfo] = useState<GetFirmwareInfoResponse>();
  const [error, setError] = useState<string>();
  const requested = useRef(false);

  useEffect(() => {
    if (!ready || !subsystem || requested.current) return;
    requested.current = true;
    void enqueueRpc(() => call({ getFirmwareInfo: {} }))
      .then((response) => {
        if (response?.firmwareInfo) setInfo(response.firmwareInfo);
        else setError(response?.error?.message ?? "ファームウェアから予期しない応答が返されました");
      })
      .catch((reason: unknown) => {
        setError(localizedError(reason, "通信に失敗しました"));
      });
  }, [call, ready, subsystem]);

  if (!app) return null;
  if (!subsystem) return <section className="card warning" role="alert">サブシステム「{SUBSYSTEM_IDENTIFIER}」が見つかりません。DYA対応のOn the 15ファームウェアを書き込んでください。</section>;
  if (error) return <section className="card error" role="alert">ファームウェア情報の取得に失敗しました：{error}</section>;
  if (!info) return <section className="card">ファームウェア情報を読み込んでいます…</section>;
  return <section className="card"><h2>ファームウェア</h2><dl>
    <dt>バージョン</dt><dd>{info.version}</dd>
    <dt>Git SHA</dt><dd><code>{info.gitSha}</code></dd>
    <dt>スキーマバージョン</dt><dd>{info.schemaVersion}</dd>
  </dl></section>;
}

export function SchemaBadge() {
  const { ready, subsystem, call } = useCustomSubsystem(SUBSYSTEM_IDENTIFIER, {
    encode: (request: Request) => Request.encode(request).finish(),
    decode: Response.decode,
  });
  const [schemaVersion, setSchemaVersion] = useState<number>();
  const requested = useRef(false);

  useEffect(() => {
    if (!ready || !subsystem || requested.current) return;
    requested.current = true;
    void enqueueRpc(() => call({ getFirmwareInfo: {} }))
      .then((response) => setSchemaVersion(response?.firmwareInfo?.schemaVersion))
      .catch(() => setSchemaVersion(undefined));
  }, [call, ready, subsystem]);

  return schemaVersion === undefined ? null : <span>Schema {schemaVersion}</span>;
}

export function DyaStudioReturnLink() {
  return <footer className="page-footer">
    <a href="https://studio.dya.cormoran.works/">DYA Studioに戻る</a>
  </footer>;
}

export function BatterySettings() {
  const { ready, subsystem, call } = useCustomSubsystem(SUBSYSTEM_IDENTIFIER, {
    encode: (request: Request) => Request.encode(request).finish(),
    decode: Response.decode,
  });
  const [battery, setBattery] = useState<BatterySettingsResponse>();
  const [error, setError] = useState<string>();
  const [isLoading, setIsLoading] = useState(false);
  const requested = useRef(false);

  const run = async (request: Request) => {
    setIsLoading(true);
    setError(undefined);
    try {
      const response = await enqueueRpc(() => call(request));
      if (response?.batterySettings?.settings) setBattery(response.batterySettings);
      else setError(response?.error?.message ?? "ファームウェアから予期しない応答が返されました");
    } catch (reason: unknown) {
      setError(localizedError(reason, "通信に失敗しました"));
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    if (!ready || !subsystem || requested.current) return;
    requested.current = true;
    void run({ getBatterySettings: {} });
  }, [ready, subsystem]);

  if (!subsystem) return null;
  if (!battery?.settings) return <section className="card"><h2>バッテリー</h2>{error ? <p className="error" role="alert">{error}</p> : <p>バッテリー設定を読み込んでいます…</p>}</section>;

  const settings = battery.settings;
  return <section className="card"><h2>バッテリー</h2>
    {error && <p className="error" role="alert">{error}</p>}
    <label className="field">電池の種類
      <select value={settings.chemistry} disabled={isLoading} onChange={(event) => void run({ setBatterySettings: { settings: {
        ...settings, chemistry: Number(event.target.value) as BatteryChemistry,
      } } })}>
        <option value={BatteryChemistry.BATTERY_CHEMISTRY_NIMH}>NiMH</option>
        <option value={BatteryChemistry.BATTERY_CHEMISTRY_ALKALINE}>アルカリ</option>
      </select>
    </label>
    <label className="check"><input type="checkbox" checked={settings.lowWarning} disabled={isLoading}
      onChange={(event) => void run({ setBatterySettings: { settings: { ...settings, lowWarning: event.target.checked } } })} />
      バッテリー残量低下の警告
    </label>
    <p className={battery.dirty ? "unsaved" : "saved"}>{battery.dirty ? "未保存の変更あり" : "保存済み"}</p>
    <div className="buttons">
      <button disabled={isLoading || !battery.dirty} onClick={() => void run({ saveBatterySettings: {} })}>保存</button>
      <button disabled={isLoading || !battery.dirty} onClick={() => void run({ discardBatterySettings: {} })}>変更を破棄</button>
      <button disabled={isLoading} onClick={() => void run({ resetBatterySettings: {} })}>初期値に戻す</button>
    </div>
    <p className="hint">「初期値に戻す」はメモリ上だけで反映されます。再起動後も保持するには「保存」を押してください。</p>
  </section>;
}

export function StatusSettings() {
  const { ready, subsystem, call } = useCustomSubsystem(SUBSYSTEM_IDENTIFIER, {
    encode: (request: Request) => Request.encode(request).finish(),
    decode: Response.decode,
  });
  const [status, setStatus] = useState<StatusSettingsResponse>();
  const [error, setError] = useState<string>();
  const [isLoading, setIsLoading] = useState(false);
  const requested = useRef(false);

  const run = async (request: Request) => {
    setIsLoading(true);
    setError(undefined);
    try {
      const response = await enqueueRpc(() => call(request));
      if (response?.statusSettings?.settings) setStatus(response.statusSettings);
      else setError(response?.error?.message ?? "ファームウェアから予期しない応答が返されました");
    } catch (reason: unknown) {
      setError(localizedError(reason, "通信に失敗しました"));
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    if (!ready || !subsystem || requested.current) return;
    requested.current = true;
    void run({ getStatusSettings: {} });
  }, [ready, subsystem]);

  if (!subsystem) return null;
  if (!status?.settings) return <section className="card"><h2>インジケーター</h2>{error ? <p className="error" role="alert">{error}</p> : <p>状態設定を読み込んでいます…</p>}</section>;

  const settings = status.settings;
  // SetStatusSettings replaces the whole struct on the firmware side, and an
  // omitted protobuf bool arrives as false - so send every switch each time,
  // overriding only the one the user just toggled.
  const setIndicator = (change: Partial<typeof settings>) =>
    void run({
      setStatusSettings: {
        settings: {
          connectedIndicator: settings.connectedIndicator,
          disconnectedIndicator: settings.disconnectedIndicator,
          layerChangeIndicator: settings.layerChangeIndicator,
          feedbackIndicator: settings.feedbackIndicator,
          ...change,
        },
      },
    });

  const switches: { key: keyof typeof settings; label: string }[] = [
    { key: "connectedIndicator", label: "接続中は緑色のLEDを表示" },
    { key: "disconnectedIndicator", label: "未接続は赤色のLEDを点滅" },
    { key: "layerChangeIndicator", label: "レイヤー切り替え時にレイヤー番号の回数だけ緑色のLEDを点滅" },
    { key: "feedbackIndicator", label: "設定・Bluetooth操作のフィードバックを表示" },
  ];

  return <section className="card"><h2>インジケーター</h2>
    {error && <p className="error" role="alert">{error}</p>}
    {switches.map(({ key, label }) => (
      <label className="check" key={key}>
        <input type="checkbox" checked={Boolean(settings[key])} disabled={isLoading}
          onChange={(event) => setIndicator({ [key]: event.target.checked })} />
        {label}
      </label>
    ))}
    <p className={status.dirty ? "unsaved" : "saved"}>{status.dirty ? "未保存の変更あり" : "保存済み"}</p>
    <div className="buttons">
      <button disabled={isLoading || !status.dirty} onClick={() => void run({ saveStatusSettings: {} })}>保存</button>
      <button disabled={isLoading || !status.dirty} onClick={() => void run({ discardStatusSettings: {} })}>変更を破棄</button>
      <button disabled={isLoading} onClick={() => void run({ resetStatusSettings: {} })}>初期値に戻す</button>
    </div>
    <p className="hint">レイヤー通知はBaseレイヤーへ戻った時には出ません。バッテリー残量低下の警告は電池設定の「低電池警告」で切り替えます。</p>
  </section>;
}

/*
 * Hue and saturation picker. The sliders remain the keyboard and screen reader
 * path, so the wheel itself stays out of the accessibility tree.
 */
function ColorWheel({ hue, saturation, disabled, onPreview, onCommit }: {
  hue: number; saturation: number; disabled: boolean;
  onPreview: (hue: number, saturation: number) => void;
  onCommit: (hue: number, saturation: number) => void;
}) {
  const dragging = useRef(false);
  const read = (event: React.PointerEvent<HTMLDivElement>) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const x = event.clientX - rect.left - rect.width / 2;
    const y = event.clientY - rect.top - rect.height / 2;
    const distance = Math.min(1, Math.hypot(x, y) / (rect.width / 2));
    return {
      hue: Math.round(Math.atan2(x, -y) * 180 / Math.PI + 360) % 360,
      saturation: Math.round(distance * 100),
    };
  };
  const finish = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!dragging.current) return;
    dragging.current = false;
    const picked = read(event);
    onCommit(picked.hue, picked.saturation);
  };
  const angle = hue * Math.PI / 180;
  const offset = saturation / 2;
  return <div className={disabled ? "wheel disabled" : "wheel"} aria-hidden="true"
    onPointerDown={(event) => {
      if (disabled) return;
      dragging.current = true;
      event.currentTarget.setPointerCapture(event.pointerId);
      const picked = read(event);
      onPreview(picked.hue, picked.saturation);
    }}
    onPointerMove={(event) => {
      if (!dragging.current) return;
      const picked = read(event);
      onPreview(picked.hue, picked.saturation);
    }}
    onPointerUp={finish} onPointerCancel={finish} onLostPointerCapture={finish}>
    <span className="wheel-marker" style={{
      left: `${50 + Math.sin(angle) * offset}%`,
      top: `${50 - Math.cos(angle) * offset}%`,
    }} />
  </div>;
}

const EFFECT_LABELS: Record<number, string> = {
  [LightingEffect.LIGHTING_EFFECT_STATIC]: "固定色",
  [LightingEffect.LIGHTING_EFFECT_BREATHING]: "ブリージング",
  [LightingEffect.LIGHTING_EFFECT_RIPPLE]: "リップル",
  [LightingEffect.LIGHTING_EFFECT_RAINBOW]: "レインボー",
  [LightingEffect.LIGHTING_EFFECT_RAINBOW_WAVE]: "レインボー波",
  [LightingEffect.LIGHTING_EFFECT_SWEEP]: "スイープ",
  [LightingEffect.LIGHTING_EFFECT_CANDLE]: "キャンドル",
  [LightingEffect.LIGHTING_EFFECT_HEATMAP]: "ヒートマップ",
  [LightingEffect.LIGHTING_EFFECT_RAINDROPS]: "レインドロップ",
};

/* Bit N of a mask refers to effect N. An absent mask means "assume it applies",
 * so firmware without the effect list still shows every control. */
const maskHas = (mask: number | undefined, effect: number) =>
  mask === undefined || ((mask >>> effect) & 1) === 1;

export function LightingSettings() {
  const { ready, subsystem, call } = useCustomSubsystem(SUBSYSTEM_IDENTIFIER, {
    encode: (request: Request) => Request.encode(request).finish(),
    decode: Response.decode,
  });
  const [lighting, setLighting] = useState<LightingSettingsResponse>();
  const [effects, setEffects] = useState<LightingEffectsResponse>();
  const [error, setError] = useState<string>();
  const [isLoading, setIsLoading] = useState(false);
  const [hue, setHue] = useState<string>();
  const [saturation, setSaturation] = useState<string>();
  const [underglowHue, setUnderglowHue] = useState<string>();
  const [underglowSaturation, setUnderglowSaturation] = useState<string>();
  const [backlightBrightness, setBacklightBrightness] = useState<string>();
  const [underglowBrightness, setUnderglowBrightness] = useState<string>();
  const [effectSpeed, setEffectSpeed] = useState<string>();
  const requested = useRef(false);

  const run = async (request: Request) => {
    setIsLoading(true);
    setError(undefined);
    try {
      const response = await enqueueRpc(() => call(request));
      if (response?.lightingEffects) {
        setEffects(response.lightingEffects);
      } else if (response?.lightingSettings?.settings) {
        const settings = response.lightingSettings.settings;
        setLighting(response.lightingSettings);
        setHue(String(settings.hue));
        setSaturation(String(settings.saturation));
        setUnderglowHue(String(settings.underglowHue));
        setUnderglowSaturation(String(settings.underglowSaturation));
        setBacklightBrightness(String(settings.backlightBrightness));
        setUnderglowBrightness(String(settings.underglowBrightness));
        setEffectSpeed(String(settings.effectSpeed));
      } else setError(response?.error?.message ?? "ファームウェアから予期しない応答が返されました");
    } catch (reason: unknown) {
      setError(localizedError(reason, "通信に失敗しました"));
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    if (!ready || !subsystem || requested.current) return;
    requested.current = true;
    void run({ getLightingEffects: {} });
    void run({ getLightingSettings: {} });
  }, [ready, subsystem]);

  if (!subsystem) return null;
  if (!lighting?.settings) return <section className="card"><h2>ライティング</h2>{error ? <p className="error" role="alert">{error}</p> : <p>ライティング設定を読み込んでいます…</p>}</section>;

  const settings = lighting.settings;
  const preview = (changes: Partial<LightingSettingsValue>) => void run({
    setLightingSettings: { settings: { ...settings, ...changes } },
  });
  const previewRange = (changes: Partial<LightingSettingsValue>) => preview(changes);
  const supportedEffects = Object.keys(EFFECT_LABELS)
    .map(Number)
    .filter((effect) => maskHas(effects?.supported, effect));
  const usesHue = maskHas(effects?.usesHue, settings.effect);
  const usesSaturation = maskHas(effects?.usesSaturation, settings.effect);
  const usesSpeed = maskHas(effects?.usesSpeed, settings.effect);
  const backlightHue = hue ?? String(settings.hue);
  const backlightSaturation = saturation ?? String(settings.saturation);
  /* A linked underglow mirrors the backlight color instead of its own. */
  const underglowHueValue = settings.separateColor
    ? underglowHue ?? String(settings.underglowHue) : backlightHue;
  const underglowSaturationValue = settings.separateColor
    ? underglowSaturation ?? String(settings.underglowSaturation) : backlightSaturation;
  return <section className="card"><h2>ライティング</h2>
    {error && <p className="error" role="alert">{error}</p>}
    <div className="lighting-groups">
      <div className="lighting-group"><h3>バックライト</h3>
        <div className="field"><span>色相 <output>{backlightHue}°</output></span>
          <input aria-label="バックライトの色相" type="range" min="0" max="359" step="1" value={backlightHue} disabled={isLoading || !usesHue}
            onChange={(event) => setHue(event.target.value)}
            onPointerUp={(event) => previewRange({ hue: Number(event.currentTarget.value) })}
            onKeyUp={(event) => previewRange({ hue: Number(event.currentTarget.value) })} />
        </div>
        <div className="field"><span>彩度 <output>{backlightSaturation}%</output></span>
          <input aria-label="バックライトの彩度" type="range" min="0" max="100" step="1" value={backlightSaturation} disabled={isLoading || !usesSaturation}
            onChange={(event) => setSaturation(event.target.value)}
            onPointerUp={(event) => previewRange({ saturation: Number(event.currentTarget.value) })}
            onKeyUp={(event) => previewRange({ saturation: Number(event.currentTarget.value) })} />
        </div>
        <ColorWheel hue={Number(backlightHue)} saturation={Number(backlightSaturation)}
          disabled={isLoading || !usesHue}
          onPreview={(pickedHue, pickedSaturation) => {
            setHue(String(pickedHue));
            setSaturation(String(pickedSaturation));
          }}
          onCommit={(pickedHue, pickedSaturation) => previewRange({ hue: pickedHue, saturation: pickedSaturation })} />
        <div className="field"><span>明るさ <output>{backlightBrightness ?? String(settings.backlightBrightness)}%</output></span>
          <input aria-label="バックライトの明るさ" type="range" min="0" max="100" step="1" value={backlightBrightness ?? String(settings.backlightBrightness)} disabled={isLoading}
            onChange={(event) => setBacklightBrightness(event.target.value)}
            onPointerUp={(event) => previewRange({ backlightBrightness: Number(event.currentTarget.value) })}
            onKeyUp={(event) => previewRange({ backlightBrightness: Number(event.currentTarget.value) })} />
        </div>
      </div>
      <div className="lighting-group"><h3>アンダーグロー</h3>
        <div className="field"><span>色相 <output>{underglowHueValue}°</output></span>
          <input aria-label="アンダーグローの色相" type="range" min="0" max="359" step="1" value={underglowHueValue} disabled={isLoading || !settings.separateColor || !usesHue}
            onChange={(event) => setUnderglowHue(event.target.value)}
            onPointerUp={(event) => previewRange({ underglowHue: Number(event.currentTarget.value) })}
            onKeyUp={(event) => previewRange({ underglowHue: Number(event.currentTarget.value) })} />
        </div>
        <div className="field"><span>彩度 <output>{underglowSaturationValue}%</output></span>
          <input aria-label="アンダーグローの彩度" type="range" min="0" max="100" step="1" value={underglowSaturationValue} disabled={isLoading || !settings.separateColor || !usesSaturation}
            onChange={(event) => setUnderglowSaturation(event.target.value)}
            onPointerUp={(event) => previewRange({ underglowSaturation: Number(event.currentTarget.value) })}
            onKeyUp={(event) => previewRange({ underglowSaturation: Number(event.currentTarget.value) })} />
        </div>
        <ColorWheel hue={Number(underglowHueValue)} saturation={Number(underglowSaturationValue)}
          disabled={isLoading || !settings.separateColor || !usesHue}
          onPreview={(pickedHue, pickedSaturation) => {
            setUnderglowHue(String(pickedHue));
            setUnderglowSaturation(String(pickedSaturation));
          }}
          onCommit={(pickedHue, pickedSaturation) =>
            previewRange({ underglowHue: pickedHue, underglowSaturation: pickedSaturation })} />
        <div className="field"><span>明るさ <output>{underglowBrightness ?? String(settings.underglowBrightness)}%</output></span>
          <input aria-label="アンダーグローの明るさ" type="range" min="0" max="100" step="1" value={underglowBrightness ?? String(settings.underglowBrightness)} disabled={isLoading}
            onChange={(event) => setUnderglowBrightness(event.target.value)}
            onPointerUp={(event) => previewRange({ underglowBrightness: Number(event.currentTarget.value) })}
            onKeyUp={(event) => previewRange({ underglowBrightness: Number(event.currentTarget.value) })} />
        </div>
      </div>
    </div>
    <label className="check"><input type="checkbox" checked={settings.separateColor} disabled={isLoading}
      onChange={(event) => preview({ separateColor: event.target.checked })} />バックライトとアンダーグローで色を分ける</label>
    {!usesHue && <p className="hint">このエフェクトは色相を自分で決めるため、色相の操作は無効です。</p>}
    {usesHue && !settings.separateColor && <p className="hint">アンダーグローはバックライトと同じ色を使います。</p>}
    <label className="field">エフェクト
      <select value={settings.effect} disabled={isLoading}
        onChange={(event) => preview({ effect: Number(event.target.value) as LightingEffect })}>
        {supportedEffects.map((effect) =>
          <option key={effect} value={effect}>{EFFECT_LABELS[effect]}</option>)}
      </select>
    </label>
    <div className="field"><span>エフェクト速度 <output>{effectSpeed ?? String(settings.effectSpeed)}</output></span>
      <input aria-label="エフェクト速度" type="range" min="1" max="10" step="1"
        value={effectSpeed ?? String(settings.effectSpeed)} disabled={isLoading || !usesSpeed}
        onChange={(event) => setEffectSpeed(event.target.value)}
        onPointerUp={(event) => previewRange({ effectSpeed: Number(event.currentTarget.value) })}
        onKeyUp={(event) => previewRange({ effectSpeed: Number(event.currentTarget.value) })} />
    </div>
    <label className="check"><input type="checkbox" checked={settings.backlightEnabled} disabled={isLoading}
      onChange={(event) => preview({ backlightEnabled: event.target.checked })} />バックライトを有効にする</label>
    <label className="check"><input type="checkbox" checked={settings.underglowEnabled} disabled={isLoading}
      onChange={(event) => preview({ underglowEnabled: event.target.checked })} />アンダーグローを有効にする</label>
    <label className="check"><input type="checkbox" checked={settings.backlightLayerColor} disabled={isLoading}
      onChange={(event) => preview({ backlightLayerColor: event.target.checked })} />レイヤーに合わせてバックライトの色を変更</label>
    <label className="check"><input type="checkbox" checked={settings.underglowLayerColor} disabled={isLoading}
      onChange={(event) => preview({ underglowLayerColor: event.target.checked })} />レイヤーに合わせてアンダーグローの色を変更</label>
    <label className="check"><input type="checkbox" checked={settings.autoOff} disabled={isLoading}
      onChange={(event) => preview({ autoOff: event.target.checked })} />無操作時に自動消灯</label>
    <p className={lighting.dirty ? "unsaved" : "saved"}>{lighting.dirty ? "未保存の変更あり" : "保存済み"}</p>
    <div className="buttons">
      <button disabled={isLoading || !lighting.dirty} onClick={() => void run({ saveLightingSettings: {} })}>ライティングを保存</button>
      <button disabled={isLoading || !lighting.dirty} onClick={() => void run({ discardLightingSettings: {} })}>変更を破棄</button>
      <button disabled={isLoading} onClick={() => void run({ resetLightingSettings: {} })}>初期値に戻す</button>
    </div>
    <p className="hint">変更はメモリ上でプレビューされます。次回起動後も保持するには保存してください。</p>
  </section>;
}

const activityLabels: Record<PowerActivity, string> = {
  [PowerActivity.POWER_ACTIVITY_ACTIVE]: "動作中",
  [PowerActivity.POWER_ACTIVITY_IDLE]: "アイドル",
  [PowerActivity.POWER_ACTIVITY_SLEEP]: "スリープ",
  [PowerActivity.UNRECOGNIZED]: "不明",
};

const transportLabels: Record<SelectedTransport, string> = {
  [SelectedTransport.SELECTED_TRANSPORT_NONE]: "なし",
  [SelectedTransport.SELECTED_TRANSPORT_USB]: "USB",
  [SelectedTransport.SELECTED_TRANSPORT_BLE]: "Bluetooth",
  [SelectedTransport.UNRECOGNIZED]: "不明",
};

export function PowerDiagnosticsCard() {
  const { ready, subsystem, call } = useCustomSubsystem(SUBSYSTEM_IDENTIFIER, {
    encode: (request: Request) => Request.encode(request).finish(),
    decode: Response.decode,
  });
  const [diagnostics, setDiagnostics] = useState<PowerDiagnostics>();
  const [error, setError] = useState<string>();
  const [isRefreshing, setIsRefreshing] = useState(false);
  const requested = useRef(false);

  const refreshDiagnostics = async () => {
    setIsRefreshing(true);
    setError(undefined);
    try {
      const response = await enqueueRpc(() => call({ getPowerDiagnostics: {} }));
      if (response?.powerDiagnostics) setDiagnostics(response.powerDiagnostics);
      else setError(response?.error?.message ?? "診断情報として予期しない応答が返されました");
    } catch (reason: unknown) {
      setError(localizedError(reason, "通信に失敗しました"));
    } finally {
      setIsRefreshing(false);
    }
  };

  useEffect(() => {
    if (!ready || !subsystem || requested.current) return;
    requested.current = true;
    void refreshDiagnostics();
  }, [ready, subsystem]);

  if (!subsystem) return null;
  return <section className="card"><h2>電源診断</h2>
    {error && <p className="error" role="alert">{error}</p>}
    {diagnostics ? <dl>
      <dt>稼働時間</dt><dd>{Math.floor(diagnostics.uptimeMs / 1000)}秒</dd>
      <dt>無操作時間</dt><dd>{Math.floor(diagnostics.inactiveMs / 1000)}秒</dd>
      <dt>スリープまで</dt><dd>{(diagnostics.deepSleepRemainingMs / 60000).toFixed(1)}分</dd>
      <dt>USB給電</dt><dd>{diagnostics.usbPowered ? "あり" : "なし"}</dd>
      <dt>動作状態</dt><dd>{activityLabels[diagnostics.activity]}</dd>
      <dt>接続方式</dt><dd>{transportLabels[diagnostics.selectedTransport]}</dd>
    </dl> : <p>診断情報を読み込んでいます…</p>}
    <button disabled={isRefreshing} onClick={() => void refreshDiagnostics()}>{isRefreshing ? "更新しています…" : "診断情報を更新"}</button>
    <p className="hint">電源設定はDYA Studio標準SettingsページのPower Managementで変更します。</p>
  </section>;
}

const THEME_STORAGE_KEY = "onthe15-studio-theme";

function readStoredTheme(): "light" | "dark" | undefined {
  try {
    const stored = localStorage.getItem(THEME_STORAGE_KEY);
    return stored === "light" || stored === "dark" ? stored : undefined;
  } catch {
    /* Private windows and blocked site data both throw here. */
    return undefined;
  }
}

export function ThemeToggle() {
  const [theme, setTheme] = useState(readStoredTheme);

  useEffect(() => {
    const root = document.documentElement;
    if (theme) root.dataset.theme = theme;
    else delete root.dataset.theme;
    try {
      if (theme) localStorage.setItem(THEME_STORAGE_KEY, theme);
      else localStorage.removeItem(THEME_STORAGE_KEY);
    } catch { /* Storing the choice is a convenience, not a requirement. */ }
  }, [theme]);

  /* Without a stored choice the OS setting decides, so start from that. */
  const isDark = theme
    ? theme === "dark"
    : window.matchMedia?.("(prefers-color-scheme: dark)").matches ?? false;
  return <button className="theme-toggle" title={isDark ? "ライトモードに切り替え" : "ダークモードに切り替え"}
    aria-label={isDark ? "ライトモードに切り替え" : "ダークモードに切り替え"}
    onClick={() => setTheme(isDark ? "light" : "dark")}>{isDark ? "☀" : "☾"}</button>;
}

export default function App() {
  return <main><ZMKConnection
      renderDisconnected={({ connect, isLoading, error }) => <section className="card connect-card">
        <ThemeToggle />
        {error && <p className="error" role="alert">{localizedError(error, "接続に失敗しました")}</p>}
        <div className="buttons">
          {isWebSerialSupported() && <button disabled={isLoading} onClick={() => connect(connectSerial)}>USBで接続</button>}
          {isWebBluetoothSupported() && <button disabled={isLoading} onClick={() => connect(gattConnect)}>Bluetoothで接続</button>}
          {!isWebSerialSupported() && !isWebBluetoothSupported() && <p>Web SerialまたはWeb Bluetoothを使用するには、Chromium系ブラウザでlocalhostを開いてください。</p>}
        </div>
        <DyaStudioReturnLink />
      </section>}
      renderConnected={({ disconnect, deviceName }) => <>
        <section className="connection-bar">
          <span><strong>接続済み</strong> {deviceName}</span>
          <span className="connection-actions"><SchemaBadge /><button onClick={disconnect}>切断</button></span>
        </section>
        <BatterySettings /><StatusSettings /><LightingSettings /><PowerDiagnosticsCard />
        <DyaStudioReturnLink />
      </>}
    />
  </main>;
}
