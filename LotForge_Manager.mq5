//+------------------------------------------------------------------+
//|                              LotForge_Manager.mq5    |
//|  Phase 6.1 — CAppDialog managed panel rewrite                    |
//|  v1.08 — SELL preview orientation fix, BE/Trailing panel rows,   |
//|           right-edge layout tightening                           |
//|                                                                  |
//|  Architecture:                                                   |
//|  · CLotForgePanel : CAppDialog — managed controls, native drag   |
//|  · Compact two-column layout: [Lots/Risk%+Entry] [TP+SL]        |
//|  · Preview lines/zones (chart-space) remain OBJ_*-based          |
//|  · Trading pipeline (BuildTradePlan→Validate→Send) unchanged     |
//|  · Status/RR info shown only in preview zone text                |
//+------------------------------------------------------------------+
#property strict
#property version   "6.10"
#property description "LotForge Manager v1.0"

#include <Trade/Trade.mqh>
#include <Controls/Dialog.mqh>
#include <Controls/Button.mqh>
#include <Controls/Edit.mqh>
#include <Controls/Label.mqh>

//+------------------------------------------------------------------+
//|  ██  ENUMS                                                       |
//+------------------------------------------------------------------+

enum TradePanelAction
  {
   ACTION_NONE         = 0,
   ACTION_BUY,
   ACTION_SELL,
   ACTION_BUY_PENDING,
   ACTION_SELL_PENDING
  };

enum PendingSubtype
  {
   PENDING_NONE  = 0,
   PENDING_STOP,
   PENDING_LIMIT
  };

enum CompactEditTarget
  {
   EDIT_TARGET_NONE   = 0,
   EDIT_TARGET_LOTS,
   EDIT_TARGET_RISK_PCT,
   EDIT_TARGET_RISK_MONEY,
   EDIT_TARGET_ENTRY,
   EDIT_TARGET_SL,
   EDIT_TARGET_TP
  };

enum RiskMode
  {
   RISK_MODE_LOTS     = 0,
   RISK_MODE_PERCENT,
   RISK_MODE_MONEY
  };

enum DragPhase
  {
   DRAG_IDLE         = 0,
   DRAG_CANDIDATE,
   DRAG_ACTIVE_LINE
  };

enum UiDispatchCommand
  {
   UI_CMD_NONE = 0,
   UI_CMD_CANCEL,
   UI_CMD_SEND,
   UI_CMD_MANUAL_BE,
   UI_CMD_MANUAL_TRAILING,
   UI_CMD_TOGGLE_AUTO_BE,
   UI_CMD_TOGGLE_AUTO_TRAILING,
   UI_CMD_TOGGLE_ALGO_TRADING
  };

//+------------------------------------------------------------------+
//|  ██  INPUTS                                                      |
//+------------------------------------------------------------------+

input group "=== Ordem ==="
input long     InpMagicNumber          = 20260404;
input int      InpDeviationPoints      = 20;
input double   InpDefaultLots          = 0.01;
input double   InpDefaultSlPoints      = 100.0;
input double   InpDefaultTpPoints      = 100.0;
input int      InpEntryStepPoints      = 10;
input int      InpDistanceStepPoints   = 10;

input group "=== Risco ==="
input RiskMode InpRiskMode             = RISK_MODE_LOTS;
input double   InpRiskPercent          = 1.0;
input double   InpRiskMoney            = 1.0;   // risco fixo na moeda da conta

input group "=== Custos ==="
input double   InpCommissionPerLot     = 0.0;   // comissão por lado, por 1.00 lote, na moeda da conta

input group "=== Painel ==="
input int      InpPanelX               = 30;
input int      InpPanelY               = 40;
input bool     InpShowPreview          = true;
input bool     InpShowRRZone           = true;

input group "=== Gestão de Posição ==="
input int      InpBEProtectOffsetPts   = 1;      // BE protect offset em pontos (evitar BE seco)
input double   InpBETriggerTargetPct   = 50.0;   // Auto BE: gatilho em % do caminho até o TP (1..100)
input double   InpAlgoPartialTrigger   = 60.0;   // Gatilho parcial: % do caminho até o TP
input double   InpAlgoPartialClosePct  = 50.0;   // Fechamento parcial: % da posição a fechar
input int      InpTrailingDistPts      = 0;      // Distância trailing em pontos (0 = usa risco inicial)
input bool     InpTrailingRequiresBE   = true;   // Trailing só atua após BE ativo na posição

input group "=== Markers de Posição Aberta ==="
input bool     InpShowMidTargetBlock   = true;   // Mostrar bloco de alvo médio (parcial) no gráfico

//+------------------------------------------------------------------+
//|  ██  CONSTANTES DE LAYOUT                                        |
//+------------------------------------------------------------------+

// ── Prefixos de objetos ───────────────────────────────────────────
const string PANEL_PREFIX          = "LFP_";
const string PREV_PFX              = "LFP_prev_";
const string MNGD_PFX             = "LFP_mngd_";   // managed open-trade markers

const string PANEL_TITLE           = "LotForge Manager v1.0";
const string PANEL_NAME            = "LotForgeMgr";            // nome interno do CAppDialog (sem espaços)
const string GV_PFX               = "LFG_";  // terminal GV prefix for chart-change save

// ── Phase 6.1: CAppDialog compact layout ──────────────────────────
const int    PANEL_W               = 350;
const int    PANEL_H               = 390;   // v2.1: +Auto BE/Trailing row

const int    ROW_H                 = 45;   // v2.0: bigger touch-friendly rows
const int    ROW_GAP               = 2;
const int    SECTION_GAP           = 5;
const int    RISK_LABEL_W          = 55;   // v2.1: same as INLINE_LABEL_W for row alignment
const int    RISK_EDIT_W           = 93;   // v2.1: matches inline edit width for symmetry
const int    INLINE_LABEL_W        = 55;   // v2.0: Entry/TP/SL label width
const int    LABEL_W               = 55;   // compat alias
const int    EDIT_W                = 94;   // compat alias (unused in new layout)
const int    EDIT_H                = 45;   // v2.0: match ROW_H
const int    SPIN_W                = 17;   // v2.0: wider spin buttons
const int    SPIN_H                = 22;   // v2.0: half of ROW_H
const int    COL_GAP               = 4;

const int    ACTION_BTN_H          = 45;   // v2.0: taller action buttons
const int    ACTION_BTN_ROW_GAP    = 2;
const int    COMMENT_BOX_H         = 0;    // v2.0: comment removed

const int    DRAG_THRESHOLD_PX     = 4;
const int    LINE_HIT_TOL_PX       = 9;
const int    PANEL_PROXIMITY_PX    = 16;

const double ENTRY_BAND_HALF_PTS   = 3.0;

//+------------------------------------------------------------------+
//|  ██  PALETA DE CORES                                             |
//+------------------------------------------------------------------+

const color  CLR_TITLE_BG          = C'0,1,204';     // #0001cc — dark outer/title blue
const color  CLR_TITLE_SHINE       = C'80,113,255';
const color  CLR_TITLE_RULE        = C'0,0,120';
const color  CLR_PANEL_BG          = C'23,103,172';  // #1767ac — inner body blue
const color  CLR_PANEL_BORDER      = C'0,40,120';
const color  CLR_TITLE_BTN         = C'188,198,201'; // #bcc6c9 — min/close/back controls
const color  CLR_COMMENT_BG        = C'215,225,238';
const color  CLR_SELL_BG           = C'250,23,15';
const color  CLR_BUY_BG            = C'0,153,0';
const color  CLR_NEUTRAL_BG        = C'208,214,224';
const color  CLR_NEUTRAL_BORDER    = C'110,120,138';
const color  CLR_SELECTED_BORDER   = C'255,214,10';
const color  CLR_STATUS_TEXT       = C'244,248,255';
const color  CLR_ENTRY_LINE        = C'76,76,76';
const color  CLR_SL_LINE           = C'205,35,55';
const color  CLR_TP_LINE           = C'45,160,70';

// ── BE / Trailing button colors ───────────────────────────────────
const color  CLR_BE_BG             = C'200,130,0';    // amber / golden
const color  CLR_BE_BORDER         = C'160,95,0';     // darker amber border
const color  CLR_TRAILING_BG       = C'105,45,185';   // deep purple
const color  CLR_TRAILING_BORDER   = C'75,25,145';    // darker purple border
const color  CLR_CHK_ON_BG         = C'0,153,0';      // same green as Buy / Buy Pending
const color  CLR_CHK_OFF_BG        = C'185,193,207';  // neutral gray when disabled

// ── 3.5: Cores do renderer de preview ────────────────────────────
const color  CLR_PREV_TP_FILL      = C'152,251,152';   // #98fb98 pale green
const color  CLR_PREV_TP_BORDER    = C'120,200,130';
const color  CLR_PREV_TP_TEXT      = C'30,140,50';     // verde escuro

const color  CLR_PREV_SL_FILL      = C'255,192,203';   // #ffc0cb pink
const color  CLR_PREV_SL_BORDER    = C'200,100,100';
const color  CLR_PREV_SL_TEXT      = C'180,20,20';     // vermelho escuro

const color  CLR_PREV_EN_FILL      = C'220,228,242';   // azul/cinza claro
const color  CLR_PREV_EN_BORDER    = C'100,130,180';
const color  CLR_PREV_EN_TEXT      = C'20,30,80';      // azul-escuro
// ── Overlay handle bar color — ice white (#f0f8ff) ─────────────────
const color  CLR_OVL_HANDLE_BG     = C'240,248,255';  // #f0f8ff — ice white
// ── Algo Trading button colors ──────────────────────────────────────
const color  CLR_ALGO_BG           = C'55,130,195';   // mid steel-blue — utility row
const color  CLR_ALGO_BORDER       = C'30,90,150';

// ── 6.2: Screen-space overlay label geometry (Position-Sizer style) ──────────
const int    OVL_PAD_X             = 4;    // left inset — tight like reference
const int    OVL_PAD_Y             = 3;    // vertical padding inside box
const int    OVL_LINE_OFFSET       = -1;   // bar overlaps line 1px — feels attached
const int    OVL_FALLBACK_CHAR_W   = 7;    // px per char if TextGetSize returns 0
const int    OVL_FALLBACK_H        = 20;   // matches OVL_BAR_H
const int    OVL_BAR_H             = 20;   // v1.09: increased from 18 for better drag target
const int    OVL_HIT_PAD_PX        = 4;    // easier overlay drag capture around the handle
enum
  {
   HANDLE_TEXT_MEASURE_CACHE_SIZE = 48,
   HANDLE_TEXT_FIT_CACHE_SIZE     = 48
  };

const ulong  SYMBOL_METADATA_TTL_MS = 10000;
const bool   PERF_TRACE_ENABLED     = false;


//+------------------------------------------------------------------+
//|  ██  STRUCT: TradeParams                                         |
//+------------------------------------------------------------------+
struct TradeParams
  {
   double   entry_price;
   double   sl_price;
   double   tp_price;
   double   sl_points;
   double   tp_points;
   double   lots;
   double   risk_pct;
   double   risk_money;
   double   reward_money;
   double   reward_pct;   // percent gain on account balance (reward_money / balance * 100)
   double   rr_ratio;

   void     Clear();
   bool     IsValid() const;
  };

//+------------------------------------------------------------------+
//|  ██  STRUCT: PanelState                                          |
//+------------------------------------------------------------------+
struct PanelState
  {
   int               panel_x;
   int               panel_y;
   bool              minimized;

   TradePanelAction  action;
   CompactEditTarget active_edit;

   double            lots;
   double            entry_price;
   double            sl_points;
   double            tp_points;
   double            market_sl_price;
   double            market_tp_price;
   string            order_comment;

   RiskMode          risk_mode;
   double            risk_percent;
   double            risk_money;

   bool              entry_line_visible;
   bool              sl_line_visible;
   bool              tp_line_visible;
   bool              rr_zone_visible;

   bool              break_even_enabled;
   int               break_even_points;
   bool              trailing_stop_enabled;
   int               trailing_stop_points;
   bool              algo_trading_ui_enabled;  // toggle-row UI state

   bool              preview_busy;
   bool              syncing;

   bool              edit_in_progress;
   CompactEditTarget editing_object;

   string            status_text;

   void              Init();
   void              Reset();
  };

//+------------------------------------------------------------------+
//|  ██  STRUCT: ManagedTradeState                                   |
//|  Estado por ticket para gestão automática de posição             |
//+------------------------------------------------------------------+

struct ManagedTradeState
  {
   ulong    ticket;
   string   symbol;
   double   initial_open_price;
   double   initial_sl;
   double   initial_tp;
   double   initial_risk_points;   // risco original — nunca recalculado após SL movido
   bool     be_applied;            // BE já foi aplicado nesta posição
   bool     partial_done;          // fechamento parcial já executado
   bool     trailing_armed;        // trailing armado manualmente
   bool     algo_managed;          // posição entrou no pipeline Algo Trading
  };

struct UiDispatchState
  {
   UiDispatchCommand command;
   bool              refresh_values;
   bool              refresh_action_buttons;
   bool              refresh_be_trailing_buttons;
   bool              refresh_preview;
   bool              clear_preview;
   bool              redraw;
   bool              has_order_selection;
   TradePanelAction  selected_action;

   void Reset()
     {
      command                     = UI_CMD_NONE;
      refresh_values              = false;
      refresh_action_buttons      = false;
      refresh_be_trailing_buttons = false;
      refresh_preview             = false;
      clear_preview               = false;
      redraw                      = false;
      has_order_selection         = false;
      selected_action             = ACTION_NONE;
     }
  };

struct PreviewSnapshot
  {
   bool              visible;
   TradePanelAction  action;
   bool              is_buy;
   double            entry_price;
   double            sl_price;
   double            tp_price;
   bool              plan_valid;
   double            plan_lots;
   double            risk_money;
   double            reward_money;
   double            risk_pct;
   double            reward_pct;
   string            effective_label;
   string            short_label;
   string            entry_line_tooltip;
   string            sl_line_tooltip;
   string            tp_line_tooltip;
   string            en_label;
   string            sl_label;
   string            tp_label;

   void              Clear();
  };

struct SymbolRuntimeMetadata
  {
   bool              valid;
   string            symbol;
   int               digits;
   double            volume_min;
   double            volume_max;
   double            volume_step;
   double            tick_size;
   int               stops_level;
   int               freeze_level;
   ulong             revision;
   ulong             last_refresh_ms;

   void              Clear();
  };

struct PreviewFinancialKey
  {
   bool              valid;
   TradePanelAction  action;
   RiskMode          risk_mode;
   double            risk_percent;
   double            risk_money;
   double            lots;
   double            entry_price;
   double            sl_price;
   double            tp_price;
   double            sl_points;
   double            tp_points;
   double            account_balance;
   ulong             metadata_revision;

   void              Clear();
  };

struct PreviewFinancialState
  {
   bool              ready;
   bool              plan_built;
   bool              plan_valid;
   TradeParams       plan;
   string            build_reason;
   string            validation_message;

   void              Clear();
  };

struct HandleTextMeasureCacheEntry
  {
   bool              valid;
   string            text;
   uint              width;
   uint              height;
  };

struct HandleTextFitCacheEntry
  {
   bool              valid;
   string            text;
   int               avail_w;
   string            fitted_text;
   uint              width;
   uint              height;
  };

//+------------------------------------------------------------------+
//|  ██  VARIÁVEIS GLOBAIS                                           |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|  ██  FORWARD DECLARATIONS (free functions)                       |
//+------------------------------------------------------------------+

string  ObjName(const string suffix);
bool    IsBuyAction(const TradePanelAction action);
bool    IsMarketAction(const TradePanelAction action);
bool    IsPendingAction(const TradePanelAction action);
string  ActionLabel(const TradePanelAction action);
PendingSubtype  DerivePendingSubtype(const TradePanelAction action, const double entry_price);
string  PendingSubtypeLabel(const PendingSubtype subtype);
string  EffectiveActionLabel(const TradePanelAction action, const double entry_price);
string  ShortPreviewLabel(const TradePanelAction action, const double entry_price);
bool    RefreshSymbolRuntimeMetadata(const bool force = false);
int     SymbolDigitsCached();
double  SymbolVolumeMinCached();
double  SymbolVolumeMaxCached();
double  SymbolVolumeStepCached();
double  SymbolTickSizeCached();
int     SymbolStopsLevelCached();
int     SymbolFreezeLevelCached();
ulong   CurrentSymbolMetadataRevision();
int     PriceDigits();
int     VolumeDigits();
double  NormalizePriceValue(const double price);
double  NormalizeVolumeValue(const double volume);
string  FormatLots(const double volume);
string  FormatPrice(const double price);
string  FormatPoints(const double points);
string  FormatMoney(const double value);
string  FormatPercent(const double value);
double  CurrentReferencePrice(const bool is_buy);
double  CurrentMidPrice();
bool    ParseDoubleText(string text, double &value);
void    ClearMarketPriceTargets();
void    ArmMarketPriceTargetsFromCurrentPoints();
void    SyncMarketPointsFromAbsoluteTargets(const double entry_price);
double  EffectiveStateEntryPrice(const TradePanelAction action);
double  EffectiveStateSLPrice(const TradePanelAction action, const double entry_price);
double  EffectiveStateTPPrice(const TradePanelAction action, const double entry_price);
bool    BuildTradePlan(TradeParams &params, string &out_reason);
bool    CalcLotsFromRiskMoney(const double entry_price, const double sl_price,
                              const double risk_money, const bool is_buy,
                              double &out_lots, string &out_reason);
bool    CalcLotsFromRiskPercent(const double entry_price, const double sl_price,
                                const bool is_buy, double &out_lots, string &out_reason);
bool    CalcRiskMoneyFromLots(const double entry_price, const double sl_price,
                              const double lots, const bool is_buy,
                              double &out_risk_money, string &out_reason);
bool    CalcRiskPercentFromLots(const double entry_price, const double sl_price,
                                const double lots, const bool is_buy,
                                double &out_risk_pct, string &out_reason);
bool    ValidateTradeRequest(const TradeParams &params, string &message);
bool    SendSelectedOrder(const TradeParams &plan);
void    SetStatus(const string text, const bool sticky = false);
void    EnsurePendingEntry();
void    AdjustLots(const int direction);
void    AdjustEntry(const int direction);
void    AdjustDistance(double &distance_points, const int direction);
void    HandleOrderSelection(const TradePanelAction action);
void    QueueUiRefresh(const bool refresh_values = true,
           const bool refresh_preview = true,
           const bool redraw = true);
void    QueueUiCommand(const UiDispatchCommand command);
void    QueueUiOrderSelection(const TradePanelAction action);
void    ProcessUiDispatch();
void    SyncUiInteractionState();
bool    ShouldPauseUiHeavyRefresh();
void    RequestChartRedraw();
void    FlushPendingChartRedraw();
void    TrackUiInteractionEvent(const int id,
           const long &lparam,
           const double &dparam,
           const string &sparam);
void    ProcessUiCancel();
void    ProcessUiSend();
void    ProcessUiManualBreakEven();
void    ProcessUiManualTrailing();
void    ProcessUiToggleAutoBE();
void    ProcessUiToggleAutoTrailing();
void    ProcessUiToggleAlgoTrading();
void    DeletePreviewObjects();
void    DeleteByPrefix();
void    UpdatePreview(const bool do_redraw = true);
void    UpdatePreviewGeometryOnly(const bool do_redraw = true);
void    InvalidatePreviewSnapshot();
void    InvalidatePreviewFinancialState();
void    MarkPreviewDirty();
void    MarkPreviewFinancialDirty();
bool    ShouldRefreshPreviewOnPulse();
bool    BuildPreviewGeometrySnapshot(PreviewSnapshot &snapshot);
bool    EnsurePreviewFinancialState(const PreviewSnapshot &snapshot);
void    ApplyPreviewFinancialStateToSnapshot(PreviewSnapshot &snapshot);
void    SuppressChartScroll();
void    RestoreChartScroll();
void    ResetDragState();
string  DetectOverlayBarHit(const int mx, const int my);
void    HandleNativeLineDrag(const string obj_name);
bool    ApplyLineDrag(const int mx, const int my);
void    HandleMouseMoveDrag(const long mouse_x, const double mouse_y_d, const bool btn_down);
bool    HandlePanelEdgeGrabDrag(const int mx, const int my, const bool btn_down);
void    SaveStateForChartChange();
bool    RestoreStateFromChartChange();
double  CalcSmartInitDistance();
void    EraseOverlayLabel(const string kind);
void    UpdateOverlayPreviewLabel(const string kind, const string text,
           const double price, const datetime t1, const datetime t2,
           const bool above_line,
           const color bg_clr, const color border_clr, const color txt_clr);

// ── Managed open-trade markers (independent of preview layer) ────
void    UpdateOpenTradeMarker(const string obj_id, const string text,
           const double price, const bool above_line,
           const color bg_clr, const color border_clr, const color txt_clr);
bool    RefreshManagedTradeMarkersGeometryOnly();
void    RequestManagedTradeMarkerCleanup();
void    UpdateManagedTradeMarkers(const ulong ticket);
void    EraseManagedTradeMarkers(const ulong ticket);
void    EraseAllManagedTradeMarkers();
void    RefreshAllManagedTradeMarkers();

//+------------------------------------------------------------------+
//|  ██  CLotForgePanel — CAppDialog-based managed panel             |
//|                                                                  |
//|  Replaces the old registry-based BuildPanel/MovePanel system.    |
//|  CAppDialog handles: native drag, minimize/maximize, cleanup.    |
//|  Preview objects (chart-space) remain separate — untouched.      |
//+------------------------------------------------------------------+

class CLotForgePanel : public CAppDialog
  {
private:
   // ── Row 1: Primary (Lots/Risk%) + Entry ────────────────────────
   CButton        m_BtnRiskMode;
   CEdit          m_EdtPrimary;
   CButton        m_BtnPrimaryUp;
   CButton        m_BtnPrimaryDn;
   CButton        m_LblEntry;
   CEdit          m_EdtEntry;
   CButton        m_BtnEntryUp;
   CButton        m_BtnEntryDn;

   // ── Row 2: TP + SL ────────────────────────────────────────────
   CButton        m_LblTP;
   CEdit          m_EdtTP;
   CButton        m_BtnTPUp;
   CButton        m_BtnTPDn;
   CButton        m_LblSL;
   CEdit          m_EdtSL;
   CButton        m_BtnSLUp;
   CButton        m_BtnSLDn;

   // ── Action buttons ─────────────────────────────────────────────
   CButton        m_BtnSell;
   CButton        m_BtnBuy;
   CButton        m_BtnSellPending;
   CButton        m_BtnBuyPending;
   // ── BE / Trailing row ──────────────────────────────────────────
   CButton        m_BtnBE;
   CButton        m_BtnTrailing;
   // ── Auto BE / Auto Trailing checkboxes ─────────────────────────
   CButton        m_ChkAutoBE;
   CButton        m_ChkAutoTrailing;
   // ── Algo Trading row ───────────────────────────────────────────
   CButton        m_BtnAlgoTrading;
   // ── Bottom row ─────────────────────────────────────────────────
   CButton        m_BtnCancel;
   CButton        m_BtnSend;

   // ── Layout helpers ─────────────────────────────────────────────
   int            m_col_w;       // single-column width (computed)
   int            m_content_w;   // usable width inside client area

   bool           CreateInlineGroup(const int x, const int y,
                     CButton &lbl, const string lbl_text,
                     CEdit &edt, const string edt_text,
                     CButton &btn_up, CButton &btn_dn,
                     const int lbl_w, const int edt_w);
   bool           CreateRiskModeGroup(const int x, const int y,
                     const int lbl_w, const int edt_w);
   void           SyncEditableFieldsToState(const bool include_primary = true);

public:
   bool           CreatePanel(const long chart, const string name,
                     const int subwin, const int x1, const int y1);
   void           RefreshValues(void);
   void           RefreshActionButtons(void);
   void           RefreshBETrailingButtons(void);
   void           ApplyActionStyle(CButton &btn, const color base_clr, const bool selected);
   bool           IsMouseOverPanel(const int mx, const int my);
   bool           IsMouseNearPanel(const int mx, const int my);

   // ── Protected-access wrapper ────────────────────────────────────
   // CAppDialog::Minimize() is protected; this thin public forwarder lets
   // OnInit() apply the restored minimized state from outside the class.
   void           ApplyMinimize(void) { Minimize(); }
   void           BringPanelToFront(void);
   void           RememberPanelState(void);
   void           BeginActiveEdit(const CompactEditTarget target);
   void           EndActiveEdit(void);
   bool           OwnsObject(const string obj_name);
   CompactEditTarget ResolveEditTarget(const string obj_name);
   virtual bool   OnDialogDragStart(void);
   virtual bool   OnDialogDragEnd(void);
   virtual void   OnClickCaption(void);
   virtual void   OnClickButtonMinMax(void);
   virtual void   Minimize(void);
   virtual void   Maximize(void);

   // ── Event handlers ─────────────────────────────────────────────
   void           OnClickRiskMode(void);
   void           OnClickPrimaryUp(void);
   void           OnClickPrimaryDn(void);
   void           OnClickEntryUp(void);
   void           OnClickEntryDn(void);
   void           OnClickTPUp(void);
   void           OnClickTPDn(void);
   void           OnClickSLUp(void);
   void           OnClickSLDn(void);
   void           OnClickSell(void);
   void           OnClickBuy(void);
   void           OnClickSellPending(void);
   void           OnClickBuyPending(void);
   void           OnClickCancel(void);
   void           OnClickSend(void);
   void           OnClickBE(void);
   void           OnClickTrailing(void);
   void           OnClickAutoBE(void);
   void           OnClickAutoTrailing(void);
   void           OnClickAlgoTrading(void);
   void           OnEndEditPrimary(void);
   void           OnEndEditEntry(void);
   void           OnEndEditTP(void);
   void           OnEndEditSL(void);

   virtual bool   OnEvent(const int id, const long &lparam,
                           const double &dparam, const string &sparam);
  };

//+------------------------------------------------------------------+
//|  ██  VARIÁVEIS GLOBAIS                                           |
//+------------------------------------------------------------------+

PanelState       g_state;
TradeParams      g_trade_plan;
PreviewSnapshot  g_preview_snapshot;
SymbolRuntimeMetadata g_symbol_metadata;
PreviewFinancialKey   g_preview_financial_key;
PreviewFinancialState g_preview_financial_state;
UiDispatchState  g_ui;
CTrade           g_trade;
CLotForgePanel   g_panel;

DragPhase        g_drag_phase        = DRAG_IDLE;
string           g_drag_line_kind    = "";
int              g_drag_press_x      = 0;
int              g_drag_press_y      = 0;
bool             g_native_preview_line_dragging = false;
string           g_native_preview_line_kind     = "";

bool             g_scroll_was_enabled = true;
bool             g_scroll_suppressed  = false;
bool             g_status_sticky      = false;
bool             g_preview_snapshot_ready = false;
bool             g_preview_dirty      = true;
bool             g_preview_financial_dirty = true;
double           g_preview_market_entry_key = 0.0;
int              g_preview_geometry_candle_count = 0;
datetime         g_preview_geometry_bar_right = 0;
bool             g_chart_redraw_pending = false;
HandleTextMeasureCacheEntry g_handle_text_measure_cache[HANDLE_TEXT_MEASURE_CACHE_SIZE];
HandleTextFitCacheEntry     g_handle_text_fit_cache[HANDLE_TEXT_FIT_CACHE_SIZE];
int              g_handle_text_measure_cache_next = 0;
int              g_handle_text_fit_cache_next     = 0;
bool             g_handle_text_font_ready         = false;

// ── Panel drag performance tracking ─────────────────────────────────
//  During panel drag, UpdatePreview and heavy processing are suppressed.
//  This state is now driven by the native CDialog drag hooks.
bool             g_panel_dragging     = false;
bool             g_panel_manual_dragging = false;
bool             g_panel_edge_drag_candidate = false;
int              g_panel_edge_press_x = 0;
int              g_panel_edge_press_y = 0;
int              g_panel_edge_origin_x = 0;
int              g_panel_edge_origin_y = 0;
bool             g_ui_interaction_active = false;

// ── Gestão de posição por ticket ──────────────────────────────────
ManagedTradeState  g_managed_trades[];
bool               g_algo_trading_enabled = false;   // estado lógico do Algo Trading
bool               g_managed_marker_cleanup_pending = true;
ulong              g_perf_preview_geometry_refresh_count = 0;
ulong              g_perf_preview_financial_refresh_count = 0;
ulong              g_perf_preview_overlay_only_refresh_count = 0;
ulong              g_perf_symbol_metadata_refresh_count = 0;
ulong              g_perf_symbol_metadata_refresh_failure_count = 0;

//+------------------------------------------------------------------+
//|  ██  IMPLEMENTAÇÕES EXTRAÍDAS                                   |
//+------------------------------------------------------------------+
#include "LotForge\Core.mqh"
#include "LotForge\Panel.mqh"
#include "LotForge\Trading.mqh"
#include "LotForge\Preview.mqh"
#include "LotForge\Management.mqh"

//+------------------------------------------------------------------+
//|  ██  OnInit                                                      |
//+------------------------------------------------------------------+

int OnInit()
  {
   g_ui.Reset();
   g_symbol_metadata.Clear();
   g_preview_financial_key.Clear();
   g_preview_financial_state.Clear();
   g_ui_interaction_active = false;
   g_chart_redraw_pending = false;
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   RefreshSymbolRuntimeMetadata(true);

   // ── Detectar se é mudança de TF: g_panel e chart objects já existem ─
   bool chart_change = RestoreStateFromChartChange();

   if(chart_change)
     {
      // ── Fast-path: troca de timeframe ─────────────────────────────────
      // g_panel C++ object intacto em memória, chart objects persistem na
      // tela — simplesmente atualizamos os valores exibidos, sem recriar
      // nem redesenhar o painel.  Sem flicker, sem replot.
      g_trade_plan.Clear();
      g_panel.RefreshValues();
      g_panel.RefreshActionButtons();
      g_panel.RefreshBETrailingButtons();
      SetStatus("Selecione o tipo de ordem.");
      UpdatePreview();
      EventSetTimer(1);
      ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
      FlushPendingChartRedraw();
      return INIT_SUCCEEDED;
     }

   // ── Full init: primeira sessão ou recarregamento completo ─────────────
   g_state.Init();
   // Fresh session: use input defaults + smart initial distances
   g_state.lots    = NormalizeVolumeValue(InpDefaultLots);
   g_state.panel_x = InpPanelX;
   g_state.panel_y = InpPanelY;
   double init_dist    = CalcSmartInitDistance();
   g_state.sl_points   = init_dist;
   g_state.tp_points   = MathRound(init_dist * 1.5);   // 1:1.5 RR default

   DeleteByPrefix();
   g_trade_plan.Clear();

   // Use restored coordinates when available (REASON_CHARTCHANGE path).
   // g_state.panel_x/y already hold either the restored position or the
   // InpPanelX/Y defaults — the conditional above took care of that.
   if(!g_panel.CreatePanel(0, PANEL_NAME, 0, g_state.panel_x, g_state.panel_y))
     {
      Print("ERRO: falha ao criar painel CAppDialog");
      return INIT_FAILED;
     }

   g_panel.Run();

   // Apply restored minimized state.  Must be called AFTER Run() because
   // Run() always starts the dialog maximized internally.
   if(g_state.minimized)
      g_panel.ApplyMinimize();   // calls protected CAppDialog::Minimize() via wrapper

   SetStatus("Selecione o tipo de ordem.");
   UpdatePreview();

   EventSetTimer(1);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   FlushPendingChartRedraw();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//|  ██  OnDeinit                                                    |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
   ResetDragState();

   if(reason == REASON_CHARTCHANGE)
     {
      // ── Fast-path: mudança de timeframe ─────────────────────────────
      // A instância C++ de g_panel e todos os chart objects do CAppDialog
      // (OBJ_BUTTON, OBJ_EDIT, OBJ_RECTANGLE_LABEL) são ancorados na tela
      // e sobrevivem intactos ao ciclo deinit/init — não chamamos Destroy()
      // nem CreatePanel(), eliminando qualquer flash/replot visual.
      // Salvamos apenas o estado (posição real + valores) para o OnInit
      // detectar que é uma troca de TF e pular a recriação do painel.
      g_state.panel_x = (int)g_panel.Left();
      g_state.panel_y = (int)g_panel.Top();
      SaveStateForChartChange();
      return;   // sem ChartRedraw — nada foi removido, não há nada para redesenhar
     }

   // ── Teardown completo para todos os outros motivos de deinit ─────────
   DeletePreviewObjects();
   EraseAllManagedTradeMarkers();
   g_panel.Destroy(reason);
   DeleteByPrefix();
   RequestChartRedraw();
   FlushPendingChartRedraw();
  }

//+------------------------------------------------------------------+
//|  ██  OnTick / OnTimer                                            |
//+------------------------------------------------------------------+

void OnTick()
  {
   // ── 1. Preview update ─────────────────────────────────────────────
   //  Skip while the user is actively interacting with the panel.
   if(!ShouldPauseUiHeavyRefresh() && ShouldRefreshPreviewOnPulse())
      UpdatePreview();

   // ── 2. Sincronizar estado das posições abertas ───────────────────
   SyncManagedTradeState();

   // ── 3. Pipeline de gestão automática ────────────────────────────
   //       Executa se: Auto BE / Auto Trailing / Algo Trading ativos
   if(g_state.break_even_enabled  ||
      g_state.trailing_stop_enabled ||
      g_algo_trading_enabled)
     {
      RunAutomatedTradeManagement();
     }

   // ── 4. Atualizar markers visuais de posição aberta ───────────────
   if(!ShouldPauseUiHeavyRefresh())
      RefreshAllManagedTradeMarkers();

   FlushPendingChartRedraw();
  }

void OnTimer()
  {
   ulong metadata_revision = CurrentSymbolMetadataRevision();
   if(RefreshSymbolRuntimeMetadata() &&
      CurrentSymbolMetadataRevision() != metadata_revision)
      MarkPreviewDirty();

   // Skip while the user is actively interacting with the panel.
   if(!ShouldPauseUiHeavyRefresh() && ShouldRefreshPreviewOnPulse())
      UpdatePreview();

   FlushPendingChartRedraw();
  }

//+------------------------------------------------------------------+
//|  ██  OnChartEvent                                                |
//+------------------------------------------------------------------+

void OnChartEvent(const int id,
                  const long   &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   // ── PS pattern: filter CHART_CHANGE from CAppDialog ───────────────
   //  Position Sizer does: if (id != CHARTEVENT_CHART_CHANGE) ExtDialog.OnEvent(...)
   //  This avoids a known minimization bug on chart/TF switch and
   //  prevents CAppDialog from doing unnecessary internal work during
   //  chart resize/scroll events.
   if(id != CHARTEVENT_CHART_CHANGE)
     {
      TrackUiInteractionEvent(id, lparam, dparam, sparam);
      g_panel.ChartEvent(id, lparam, dparam, sparam);
      ProcessUiDispatch();
     }

   if(id == CHARTEVENT_CHART_CHANGE)
     {
      // During panel drag, the chart fires CHART_CHANGE frequently as
      // the panel overlay moves — do a geometry-only refresh.
      if(!ShouldPauseUiHeavyRefresh())
        {
         UpdatePreviewGeometryOnly();
         if(!RefreshManagedTradeMarkersGeometryOnly())
            RefreshAllManagedTradeMarkers();
        }
      FlushPendingChartRedraw();
      return;
     }

   // ── Native line drag (Position-Sizer pattern) ─────────────────────
   if(id == CHARTEVENT_OBJECT_DRAG)
     {
      HandleNativeLineDrag(sparam);
      FlushPendingChartRedraw();
      return;
     }

   // ── Deselect lines after single click so they don't stay highlighted ──
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(StringFind(sparam, PREV_PFX) == 0 &&
         StringFind(sparam, "_line") != -1)
        {
         ObjectSetInteger(0, sparam, OBJPROP_SELECTED, false);
         RequestChartRedraw();
        }
      FlushPendingChartRedraw();
      return;
     }

   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      bool btn_down = ((StringToInteger(sparam) & 1) != 0);
      HandleMouseMoveDrag(lparam, dparam, btn_down);
      FlushPendingChartRedraw();
      return;
     }
  }
//+------------------------------------------------------------------+
