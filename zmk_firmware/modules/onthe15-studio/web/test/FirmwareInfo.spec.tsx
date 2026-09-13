import { StrictMode } from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createConnectedMockZMKApp, ZMKAppProvider } from "@cormoran/zmk-studio-react-hook/testing";
import { call_rpc } from "@zmkfirmware/zmk-studio-ts-client";
import { BatterySettings, DyaStudioReturnLink, FirmwareInfo, LightingSettings, PowerDiagnosticsCard, SchemaBadge, StatusSettings, SUBSYSTEM_IDENTIFIER, ThemeToggle } from "../src/App";
import { BatteryChemistry, LightingEffect, PowerActivity, Response, SelectedTransport, type Response as RpcResponse } from "../src/proto/onthe15/studio/studio";

jest.mock("@zmkfirmware/zmk-studio-ts-client", () => ({ create_rpc_connection: jest.fn(), call_rpc: jest.fn() }));

const rpcResult = (response: RpcResponse) => ({
  custom: { call: { payload: Response.encode(response).finish() } },
});

beforeEach(() => jest.resetAllMocks());

describe("FirmwareInfo", () => {
  it("displays the GetFirmwareInfo response", async () => {
    const payload = Response.encode({ firmwareInfo: { version: "0.1.0", gitSha: "abc123", schemaVersion: 1 } }).finish();
    (call_rpc as jest.Mock).mockResolvedValue({ custom: { call: { payload } } });
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<ZMKAppProvider value={app}><FirmwareInfo /></ZMKAppProvider>);
    await waitFor(() => expect(screen.getByText("0.1.0")).toBeInTheDocument());
    expect(screen.getByText("abc123")).toBeInTheDocument();
    expect(screen.getByText("1")).toBeInTheDocument();
  });

  it("completes firmware loading under React StrictMode", async () => {
    (call_rpc as jest.Mock).mockResolvedValue(rpcResult({
      firmwareInfo: { version: "0.5.1", gitSha: "strict-mode", schemaVersion: 5 },
    }));
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<StrictMode><ZMKAppProvider value={app}><FirmwareInfo /></ZMKAppProvider></StrictMode>);

    await screen.findByText("0.5.1");
    expect(screen.queryByText("ファームウェア情報を読み込んでいます…")).not.toBeInTheDocument();
    expect(call_rpc).toHaveBeenCalledTimes(1);
  });

  it("reports a missing subsystem", () => {
    const app = createConnectedMockZMKApp({ subsystems: [] });
    render(<ZMKAppProvider value={app}><FirmwareInfo /></ZMKAppProvider>);
    expect(screen.getByRole("alert")).toHaveTextContent(`サブシステム「${SUBSYSTEM_IDENTIFIER}」が見つかりません`);
  });
});

describe("SchemaBadge", () => {
  it("shows only the compatibility schema", async () => {
    (call_rpc as jest.Mock).mockResolvedValue(rpcResult({
      firmwareInfo: { version: "hidden", gitSha: "hidden-sha", schemaVersion: 3 },
    }));
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<ZMKAppProvider value={app}><SchemaBadge /></ZMKAppProvider>);
    await screen.findByText("Schema 3");
    expect(screen.queryByText("hidden")).not.toBeInTheDocument();
    expect(screen.queryByText("hidden-sha")).not.toBeInTheDocument();
  });
});

describe("DyaStudioReturnLink", () => {
  it("links back to the stable DYA Studio", () => {
    render(<DyaStudioReturnLink />);
    expect(screen.getByRole("link", { name: "DYA Studioに戻る" }))
      .toHaveAttribute("href", "https://studio.dya.cormoran.works/");
  });
});

describe("BatterySettings", () => {
  it("previews and saves a chemistry change", async () => {
    (call_rpc as jest.Mock)
      .mockResolvedValueOnce(rpcResult({ batterySettings: { settings: {
        chemistry: BatteryChemistry.BATTERY_CHEMISTRY_NIMH, lowWarning: true,
      }, dirty: false } }))
      .mockResolvedValueOnce(rpcResult({ batterySettings: { settings: {
        chemistry: BatteryChemistry.BATTERY_CHEMISTRY_ALKALINE, lowWarning: true,
      }, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ batterySettings: { settings: {
        chemistry: BatteryChemistry.BATTERY_CHEMISTRY_ALKALINE, lowWarning: true,
      }, dirty: false } }));
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<ZMKAppProvider value={app}><BatterySettings /></ZMKAppProvider>);

    const chemistry = await screen.findByLabelText("電池の種類");
    await userEvent.selectOptions(chemistry, String(BatteryChemistry.BATTERY_CHEMISTRY_ALKALINE));
    await screen.findByText("未保存の変更あり");
    await userEvent.click(screen.getByRole("button", { name: "保存" }));
    await screen.findByText("保存済み");
    expect(call_rpc).toHaveBeenCalledTimes(3);
  });

  it("discards a preview and resets to defaults in memory", async () => {
    const alkaline = { chemistry: BatteryChemistry.BATTERY_CHEMISTRY_ALKALINE, lowWarning: false };
    const defaults = { chemistry: BatteryChemistry.BATTERY_CHEMISTRY_NIMH, lowWarning: true };
    (call_rpc as jest.Mock)
      .mockResolvedValueOnce(rpcResult({ batterySettings: { settings: alkaline, dirty: false } }))
      .mockResolvedValueOnce(rpcResult({ batterySettings: { settings: { ...alkaline, lowWarning: true }, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ batterySettings: { settings: alkaline, dirty: false } }))
      .mockResolvedValueOnce(rpcResult({ batterySettings: { settings: defaults, dirty: true } }));
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<ZMKAppProvider value={app}><BatterySettings /></ZMKAppProvider>);

    const warning = await screen.findByRole("checkbox", { name: "バッテリー残量低下の警告" });
    await userEvent.click(warning);
    await screen.findByText("未保存の変更あり");
    await userEvent.click(screen.getByRole("button", { name: "変更を破棄" }));
    await screen.findByText("保存済み");
    await userEvent.click(screen.getByRole("button", { name: "初期値に戻す" }));
    await screen.findByText("未保存の変更あり");
    expect(screen.getByLabelText("電池の種類")).toHaveValue(String(BatteryChemistry.BATTERY_CHEMISTRY_NIMH));
    expect(warning).toBeChecked();
  });

  it("serializes the firmware and battery requests made on connect", async () => {
    let active = 0;
    let maximumActive = 0;
    let requestIndex = 0;
    (call_rpc as jest.Mock).mockImplementation(async () => {
      active += 1;
      maximumActive = Math.max(maximumActive, active);
      await new Promise((resolve) => setTimeout(resolve, 5));
      active -= 1;
      requestIndex += 1;
      return requestIndex === 1
        ? rpcResult({ firmwareInfo: { version: "0.2.0", gitSha: "def456", schemaVersion: 1 } })
        : rpcResult({ batterySettings: { settings: {
          chemistry: BatteryChemistry.BATTERY_CHEMISTRY_NIMH, lowWarning: true,
        }, dirty: false } });
    });
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<ZMKAppProvider value={app}><FirmwareInfo /><BatterySettings /></ZMKAppProvider>);

    await screen.findByText("0.2.0");
    await screen.findByLabelText("電池の種類");
    expect(maximumActive).toBe(1);
    expect(call_rpc).toHaveBeenCalledTimes(2);
  });
});

describe("StatusSettings", () => {
  it("previews, discards, saves, and resets the connected indicator", async () => {
    const off = { connectedIndicator: false };
    const on = { connectedIndicator: true };
    (call_rpc as jest.Mock)
      .mockResolvedValueOnce(rpcResult({ statusSettings: { settings: off, dirty: false } }))
      .mockResolvedValueOnce(rpcResult({ statusSettings: { settings: on, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ statusSettings: { settings: off, dirty: false } }))
      .mockResolvedValueOnce(rpcResult({ statusSettings: { settings: on, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ statusSettings: { settings: on, dirty: false } }))
      .mockResolvedValueOnce(rpcResult({ statusSettings: { settings: off, dirty: true } }));
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<ZMKAppProvider value={app}><StatusSettings /></ZMKAppProvider>);

    const connected = await screen.findByRole("checkbox", { name: "接続中は緑色のLEDを表示" });
    await userEvent.click(connected);
    await screen.findByText("未保存の変更あり");
    await userEvent.click(screen.getByRole("button", { name: "変更を破棄" }));
    await screen.findByText("保存済み");
    expect(connected).not.toBeChecked();
    await userEvent.click(connected);
    await userEvent.click(screen.getByRole("button", { name: "保存" }));
    await screen.findByText("保存済み");
    await userEvent.click(screen.getByRole("button", { name: "初期値に戻す" }));
    await screen.findByText("未保存の変更あり");
    expect(connected).not.toBeChecked();
    expect(call_rpc).toHaveBeenCalledTimes(6);
  });
});

describe("LightingSettings", () => {
  const defaults = {
    hue: 180, saturation: 80, backlightBrightness: 40, underglowBrightness: 30,
    underglowHue: 180, underglowSaturation: 80, separateColor: false,
    backlightEnabled: true, underglowEnabled: true, autoOff: true,
    effect: LightingEffect.LIGHTING_EFFECT_STATIC, effectSpeed: 5,
    backlightLayerColor: false, underglowLayerColor: false,
  };

  it("previews all SK6812 fields and saves them", async () => {
    const changed = {
      ...defaults, hue: 359, saturation: 100, backlightBrightness: 75,
      underglowBrightness: 65, backlightEnabled: false, underglowEnabled: false, autoOff: false,
      effect: LightingEffect.LIGHTING_EFFECT_BREATHING, effectSpeed: 8,
      backlightLayerColor: true, underglowLayerColor: true,
    };
    const backlightChanged = { ...defaults, backlightEnabled: false };
    const underglowChanged = { ...backlightChanged, underglowEnabled: false };
    const backlightLayerChanged = { ...underglowChanged, backlightLayerColor: true };
    const underglowLayerChanged = { ...backlightLayerChanged, underglowLayerColor: true };
    const effectChanged = { ...underglowLayerChanged, effect: LightingEffect.LIGHTING_EFFECT_BREATHING };
    const hueChanged = { ...effectChanged, hue: 359 };
    const saturationChanged = { ...hueChanged, saturation: 100 };
    const backlightBrightnessChanged = { ...saturationChanged, backlightBrightness: 75 };
    const underglowBrightnessChanged = { ...backlightBrightnessChanged, underglowBrightness: 65 };
    const speedChanged = { ...underglowBrightnessChanged, effectSpeed: 8 };
    (call_rpc as jest.Mock)
      .mockResolvedValueOnce(rpcResult({ lightingEffects: { supported: 0x1ff, usesHue: 0x1ff, usesSaturation: 0x1ff, usesSpeed: 0x1ff } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: defaults, dirty: false } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: backlightChanged, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: underglowChanged, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: backlightLayerChanged, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: underglowLayerChanged, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: effectChanged, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: hueChanged, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: saturationChanged, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: backlightBrightnessChanged, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: underglowBrightnessChanged, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: speedChanged, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: changed, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: changed, dirty: false } }));
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<ZMKAppProvider value={app}><LightingSettings /></ZMKAppProvider>);

    const backlightEnabled = await screen.findByRole("checkbox", { name: "バックライトを有効にする" });
    await userEvent.click(backlightEnabled);
    await waitFor(() => expect(backlightEnabled).not.toBeDisabled());
    const underglowEnabled = screen.getByRole("checkbox", { name: "アンダーグローを有効にする" });
    await userEvent.click(underglowEnabled);
    await waitFor(() => expect(underglowEnabled).not.toBeDisabled());
    const backlightLayerColor = screen.getByRole("checkbox", { name: "レイヤーに合わせてバックライトの色を変更" });
    await userEvent.click(backlightLayerColor);
    await waitFor(() => expect(backlightLayerColor).not.toBeDisabled());
    const underglowLayerColor = screen.getByRole("checkbox", { name: "レイヤーに合わせてアンダーグローの色を変更" });
    await userEvent.click(underglowLayerColor);
    await waitFor(() => expect(underglowLayerColor).not.toBeDisabled());
    await userEvent.selectOptions(screen.getByLabelText("エフェクト"), String(LightingEffect.LIGHTING_EFFECT_BREATHING));
    await waitFor(() => expect(screen.getByLabelText("エフェクト")).not.toBeDisabled());
    for (const [label, value] of [["バックライトの色相", "359"], ["バックライトの彩度", "100"], ["バックライトの明るさ", "75"], ["アンダーグローの明るさ", "65"]]) {
      const input = screen.getByLabelText(label);
      fireEvent.change(input, { target: { value } });
      fireEvent.pointerUp(input);
      await waitFor(() => expect(input).not.toBeDisabled());
    }
    const effectSpeed = screen.getByRole("slider", { name: "エフェクト速度" });
    fireEvent.change(effectSpeed, { target: { value: "8" } });
    fireEvent.pointerUp(effectSpeed);
    await waitFor(() => expect(effectSpeed).not.toBeDisabled());
    expect(call_rpc).toHaveBeenCalledTimes(12);
    expect(screen.queryByRole("button", { name: "ライティングをプレビュー" })).not.toBeInTheDocument();
    const autoOff = screen.getByRole("checkbox", { name: "無操作時に自動消灯" });
    await userEvent.click(autoOff);
    await waitFor(() => expect(autoOff).not.toBeDisabled());
    await userEvent.click(screen.getByRole("button", { name: "ライティングを保存" }));
    await screen.findByText("保存済み");
    expect(call_rpc).toHaveBeenCalledTimes(14);
  });

  it("discards a preview and resets defaults in memory", async () => {
    const changed = { ...defaults, hue: 90 };
    (call_rpc as jest.Mock)
      .mockResolvedValueOnce(rpcResult({ lightingEffects: { supported: 0x1ff, usesHue: 0x1ff, usesSaturation: 0x1ff, usesSpeed: 0x1ff } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: defaults, dirty: false } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: changed, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: defaults, dirty: false } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: { ...defaults, hue: 0 }, dirty: true } }));
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<ZMKAppProvider value={app}><LightingSettings /></ZMKAppProvider>);

    const hue = await screen.findByLabelText("バックライトの色相");
    fireEvent.change(hue, { target: { value: "90" } });
    fireEvent.pointerUp(hue);
    await waitFor(() => expect(hue).not.toBeDisabled());
    await userEvent.click(screen.getByRole("button", { name: "変更を破棄" }));
    await screen.findByText("保存済み");
    expect(hue).toHaveValue("180");
    await userEvent.click(screen.getByRole("button", { name: "初期値に戻す" }));
    await screen.findByText("未保存の変更あり");
    expect(hue).toHaveValue("0");
  });

  it("mirrors the backlight color until the underglow is separated", async () => {
    const separated = { ...defaults, separateColor: true };
    const recolored = { ...separated, underglowHue: 20, underglowSaturation: 60 };
    (call_rpc as jest.Mock)
      .mockResolvedValueOnce(rpcResult({ lightingEffects: { supported: 0x1ff, usesHue: 0x1ff, usesSaturation: 0x1ff, usesSpeed: 0x1ff } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: defaults, dirty: false } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: separated, dirty: true } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: recolored, dirty: true } }));
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<ZMKAppProvider value={app}><LightingSettings /></ZMKAppProvider>);

    const underglowHue = await screen.findByLabelText("アンダーグローの色相");
    expect(underglowHue).toBeDisabled();
    expect(underglowHue).toHaveValue("180");

    await userEvent.click(screen.getByRole("checkbox", { name: "バックライトとアンダーグローで色を分ける" }));
    await waitFor(() => expect(underglowHue).not.toBeDisabled());
    fireEvent.change(underglowHue, { target: { value: "20" } });
    fireEvent.pointerUp(underglowHue);
    await waitFor(() => expect(screen.getByLabelText("アンダーグローの彩度")).toHaveValue("60"));
    expect(screen.getByLabelText("バックライトの色相")).toHaveValue("180");
  });

  it("offers only the effects the firmware reports and greys out the rest", async () => {
    /* Static, breathing and rainbow only; rainbow drives its own hue. */
    const rainbow = { ...defaults, effect: LightingEffect.LIGHTING_EFFECT_RAINBOW };
    (call_rpc as jest.Mock)
      .mockResolvedValueOnce(rpcResult({ lightingEffects: {
        supported: 0b1011, usesHue: 0b0011, usesSaturation: 0b1011, usesSpeed: 0b1010,
      } }))
      .mockResolvedValueOnce(rpcResult({ lightingSettings: { settings: rainbow, dirty: false } }));
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<ZMKAppProvider value={app}><LightingSettings /></ZMKAppProvider>);

    const effect = await screen.findByLabelText("エフェクト");
    expect(screen.getAllByRole("option").map((option) => option.textContent))
      .toEqual(["固定色", "ブリージング", "レインボー"]);
    expect(effect).toHaveValue(String(LightingEffect.LIGHTING_EFFECT_RAINBOW));
    expect(screen.getByLabelText("バックライトの色相")).toBeDisabled();
    expect(screen.getByLabelText("バックライトの彩度")).not.toBeDisabled();
    expect(screen.getByLabelText("エフェクト速度")).not.toBeDisabled();
  });

  it("serializes all four initial connected RPC requests", async () => {
    let active = 0;
    let maximumActive = 0;
    let index = 0;
    const responses = [
      { firmwareInfo: { version: "0.4.0", gitSha: "phase4", schemaVersion: 4 } },
      { batterySettings: { settings: { chemistry: BatteryChemistry.BATTERY_CHEMISTRY_NIMH, lowWarning: true }, dirty: false } },
      { statusSettings: { settings: { connectedIndicator: true }, dirty: false } },
      { lightingEffects: { supported: 0x1ff, usesHue: 0x1ff, usesSaturation: 0x1ff, usesSpeed: 0x1ff } },
      { lightingSettings: { settings: defaults, dirty: false } },
    ];
    (call_rpc as jest.Mock).mockImplementation(async () => {
      active += 1; maximumActive = Math.max(maximumActive, active);
      await new Promise((resolve) => setTimeout(resolve, 3));
      active -= 1;
      return rpcResult(responses[index++]);
    });
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<ZMKAppProvider value={app}><FirmwareInfo /><BatterySettings /><StatusSettings /><LightingSettings /></ZMKAppProvider>);
    await screen.findByLabelText("バックライトの色相");
    expect(maximumActive).toBe(1);
    expect(call_rpc).toHaveBeenCalledTimes(5);
  });
});

describe("PowerDiagnosticsCard", () => {
  const diagnostics = {
    uptimeMs: 7_200_000, inactiveMs: 15_000, deepSleepRemainingMs: 1_785_000,
    usbPowered: true, activity: PowerActivity.POWER_ACTIVITY_ACTIVE,
    selectedTransport: SelectedTransport.SELECTED_TRANSPORT_USB,
  };

  it("renders and refreshes diagnostics", async () => {
    const refreshed = {
      ...diagnostics, uptimeMs: 7_260_000, usbPowered: false,
      activity: PowerActivity.POWER_ACTIVITY_IDLE,
      selectedTransport: SelectedTransport.SELECTED_TRANSPORT_BLE,
    };
    (call_rpc as jest.Mock)
      .mockResolvedValueOnce(rpcResult({ powerDiagnostics: diagnostics }))
      .mockResolvedValueOnce(rpcResult({ powerDiagnostics: refreshed }));
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<ZMKAppProvider value={app}><PowerDiagnosticsCard /></ZMKAppProvider>);

    await screen.findByText("7200秒");
    expect(screen.queryByLabelText("アイドル移行時間")).not.toBeInTheDocument();
    expect(screen.queryByLabelText("ディープスリープ移行時間")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "電源設定を保存" })).not.toBeInTheDocument();
    expect(screen.getByText("電源設定はDYA Studio標準SettingsページのPower Managementで変更します。")).toBeInTheDocument();
    expect(screen.getByText("動作中")).toBeInTheDocument();
    expect(screen.getByText("USB")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "診断情報を更新" }));
    await screen.findByText("7260秒");
    expect(screen.getByText("アイドル")).toBeInTheDocument();
    expect(screen.getByText("Bluetooth")).toBeInTheDocument();
    expect(screen.getByText("なし")).toBeInTheDocument();
  });

  it("serializes all five initial connected RPC requests", async () => {
    let active = 0;
    let maximumActive = 0;
    let index = 0;
    const lighting = {
      hue: 180, saturation: 80, backlightBrightness: 40, underglowBrightness: 30,
      underglowHue: 180, underglowSaturation: 80, separateColor: false,
      backlightEnabled: true, underglowEnabled: true, autoOff: true,
    };
    const responses: RpcResponse[] = [
      { firmwareInfo: { version: "0.5.0", gitSha: "phase5", schemaVersion: 5 } },
      { batterySettings: { settings: { chemistry: BatteryChemistry.BATTERY_CHEMISTRY_NIMH, lowWarning: true }, dirty: false } },
      { statusSettings: { settings: { connectedIndicator: true }, dirty: false } },
      { lightingEffects: { supported: 0x1ff, usesHue: 0x1ff, usesSaturation: 0x1ff, usesSpeed: 0x1ff } },
      { lightingSettings: { settings: lighting, dirty: false } },
      { powerDiagnostics: diagnostics },
    ];
    (call_rpc as jest.Mock).mockImplementation(async () => {
      active += 1; maximumActive = Math.max(maximumActive, active);
      await new Promise((resolve) => setTimeout(resolve, 3));
      active -= 1;
      return rpcResult(responses[index++]);
    });
    const app = createConnectedMockZMKApp({ subsystems: [SUBSYSTEM_IDENTIFIER] });
    render(<ZMKAppProvider value={app}><FirmwareInfo /><BatterySettings /><StatusSettings /><LightingSettings /><PowerDiagnosticsCard /></ZMKAppProvider>);
    await screen.findByText("7200秒");
    expect(maximumActive).toBe(1);
    expect(call_rpc).toHaveBeenCalledTimes(6);
  });
});

describe("ThemeToggle", () => {
  afterEach(() => {
    delete document.documentElement.dataset.theme;
    localStorage.clear();
  });

  it("switches the document theme and remembers the choice", async () => {
    render(<ThemeToggle />);
    await userEvent.click(screen.getByRole("button", { name: "ダークモードに切り替え" }));
    expect(document.documentElement.dataset.theme).toBe("dark");
    expect(localStorage.getItem("onthe15-studio-theme")).toBe("dark");
    await userEvent.click(screen.getByRole("button", { name: "ライトモードに切り替え" }));
    expect(document.documentElement.dataset.theme).toBe("light");
  });

  it("starts from the stored choice", () => {
    localStorage.setItem("onthe15-studio-theme", "dark");
    render(<ThemeToggle />);
    expect(document.documentElement.dataset.theme).toBe("dark");
    expect(screen.getByRole("button", { name: "ライトモードに切り替え" })).toBeInTheDocument();
  });
});
