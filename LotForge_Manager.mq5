//+------------------------------------------------------------------+
//|                              LotForge_Manager.mq5                 |
//|  Position Sizer & Trade Manager v1.0                              |
//|                                                                  |
//|  Architecture:                                                   |
//|  · CLotForgePanel : CAppDialog — managed controls, native drag   |
//|  · Compact two-column layout: [Lots/Risk%+Entry] [TP+SL]        |
//|  · Preview lines/zones (chart-space) remain OBJ_*-based          |
//|  · Trading pipeline (BuildTradePlan→Validate→Send) unchanged     |
//|  · Status/RR info shown only in preview zone text                |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "LotForge Manager — Position Sizer & Trade Manager v1.0"

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
   EDIT_TARGET_ENTRY,
   EDIT_TARGET_SL,
   EDIT_TARGET_TP
  };

enum RiskMode
  {
   RISK_MODE_LOTS     = 0,
   RISK_MODE_PERCENT
  };

enum DragPhase
  {
   DRAG_IDLE         = 0,
   DRAG_CANDIDATE,
   DRAG_ACTIVE_LINE
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
const string PANEL_PREFIX          = "TBP_";
const string PREV_PFX              = "TBP_prev_";
const string MNGD_PFX             = "TBP_mngd_";   // managed open-trade markers

const string PANEL_TITLE           = "LotForge Manager v1.0";
const string GV_PFX               = "LFG_";  // terminal GV prefix for chart-change save

// ── Phase 6.1: CAppDialog compact layout ──────────────────────────
const int    PANEL_W               = 340;
const int    PANEL_H               = 328;   // v1.09: +Algo Trading row (+30) + Auto rows unified (+6)

const int    ROW_H                 = 22;   // v1.07: slightly taller rows
const int    ROW_GAP               = 2;    // tight like V1.07
const int    SECTION_GAP           = 5;    // minimal gap before comment
const int    LABEL_W               = 52;   // v1.07: slightly wider label column
const int    EDIT_W                = 97;   // fills column — m_content_w=PANEL_W-6 (symmetric 3px margins)
const int    EDIT_H                = 22;   // v1.07: match ROW_H so edits fill row fully
const int    SPIN_W                = 14;
const int    SPIN_H                = 10;
const int    COL_GAP               = 4;

const int    ACTION_BTN_H          = 28;
const int    ACTION_BTN_ROW_GAP    = 2;
const int    COMMENT_BOX_H         = 22;

const int    DRAG_THRESHOLD_PX     = 4;
const int    LINE_HIT_TOL_PX       = 9;

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
const color  CLR_CHK_ON_BG         = C'45,160,70';    // green when enabled
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
const string OVL_FONT              = "Arial Bold";
const int    OVL_FONT_PTS          = 11;   // slightly larger for readability
const int    OVL_PAD_X             = 4;    // left inset — tight like reference
const int    OVL_PAD_Y             = 3;    // vertical padding inside box
const int    OVL_LINE_OFFSET       = -1;   // bar overlaps line 1px — feels attached
const int    OVL_FALLBACK_CHAR_W   = 7;    // px per char if TextGetSize returns 0
const int    OVL_FALLBACK_H        = 20;   // matches OVL_BAR_H
const int    OVL_BAR_H             = 20;   // v1.09: increased from 18 for better drag target


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
   string            order_comment;

   RiskMode          risk_mode;
   double            risk_percent;

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
bool    BuildTradePlan(TradeParams &params, string &out_reason);
bool    CalcLotsFromRiskPercent(const double entry_price, const double sl_price,
                                const bool is_buy, double &out_lots, string &out_reason);
bool    ValidateTradeRequest(const TradeParams &params, string &message);
bool    SendSelectedOrder(const TradeParams &plan);
void    SetStatus(const string text, const bool sticky = false);
void    EnsurePendingEntry();
void    AdjustLots(const int direction);
void    AdjustEntry(const int direction);
void    AdjustDistance(double &distance_points, const int direction);
void    HandleOrderSelection(const TradePanelAction action);
void    DeletePreviewObjects();
void    DeleteByPrefix();
void    UpdatePreview();
void    SuppressChartScroll();
void    RestoreChartScroll();
void    ResetDragState();
string  DetectLineHit(const int mx, const int my);
void    ApplyLineDrag(const int mx, const int my);
void    HandleMouseMoveDrag(const long mouse_x, const double mouse_y_d, const bool btn_down);
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
void    UpdateManagedTradeMarkers(const ulong ticket);
void    EraseManagedTradeMarkers(const ulong ticket);
void    EraseAllManagedTradeMarkers();

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
                     CButton &btn_up, CButton &btn_dn);
   bool           CreateRiskModeGroup(const int x, const int y);

public:
   bool           CreatePanel(const long chart, const string name,
                     const int subwin, const int x1, const int y1);
   void           RefreshValues(void);
   void           RefreshActionButtons(void);
   void           RefreshBETrailingButtons(void);
   void           ApplyActionStyle(CButton &btn, const color base_clr, const bool selected);
   bool           IsMouseOverPanel(const int mx, const int my);

   // ── Protected-access wrapper ────────────────────────────────────
   // CAppDialog::Minimize() is protected; this thin public forwarder lets
   // OnInit() apply the restored minimized state from outside the class.
   void           ApplyMinimize(void) { Minimize(); }

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
CTrade           g_trade;
CLotForgePanel   g_panel;

DragPhase        g_drag_phase        = DRAG_IDLE;
string           g_drag_line_kind    = "";
int              g_drag_press_x      = 0;
int              g_drag_press_y      = 0;

bool             g_scroll_was_enabled = true;
bool             g_scroll_suppressed  = false;
bool             g_status_sticky      = false;

// ── Gestão de posição por ticket ──────────────────────────────────
ManagedTradeState  g_managed_trades[];
bool               g_algo_trading_enabled = false;   // estado lógico do Algo Trading

//+------------------------------------------------------------------+
//|  ██  IMPLEMENTAÇÕES — helpers básicos                            |
//+------------------------------------------------------------------+

string ObjName(const string suffix) { return PANEL_PREFIX + suffix; }

bool IsBuyAction(const TradePanelAction action)
  { return (action == ACTION_BUY || action == ACTION_BUY_PENDING); }

bool IsMarketAction(const TradePanelAction action)
  { return (action == ACTION_BUY || action == ACTION_SELL); }

bool IsPendingAction(const TradePanelAction action)
  { return (action == ACTION_BUY_PENDING || action == ACTION_SELL_PENDING); }

string ActionLabel(const TradePanelAction action)
  {
   switch(action)
     {
      case ACTION_BUY:          return "Buy";
      case ACTION_SELL:         return "Sell";
      case ACTION_BUY_PENDING:  return "Buy Pending";
      case ACTION_SELL_PENDING: return "Sell Pending";
      default:                  return "None";
     }
  }

PendingSubtype DerivePendingSubtype(const TradePanelAction action,
                                    const double entry_price)
  {
   if(!IsPendingAction(action) || entry_price <= 0.0) return PENDING_NONE;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return PENDING_LIMIT;
   if(action == ACTION_BUY_PENDING)
      return (entry_price > tick.ask) ? PENDING_STOP : PENDING_LIMIT;
   else
      return (entry_price < tick.bid) ? PENDING_STOP : PENDING_LIMIT;
  }

string PendingSubtypeLabel(const PendingSubtype subtype)
  {
   switch(subtype)
     {
      case PENDING_STOP:  return " (Stop)";
      case PENDING_LIMIT: return " (Limit)";
      default:            return "";
     }
  }

string EffectiveActionLabel(const TradePanelAction action,
                            const double entry_price)
  {
   if(!IsPendingAction(action)) return ActionLabel(action);
   PendingSubtype st = DerivePendingSubtype(action, entry_price);
   return ActionLabel(action) + PendingSubtypeLabel(st);
  }
//+------------------------------------------------------------------+
//|  ShortPreviewLabel — condensed label for overlay preview bars     |
//|  Pending actions: "Buy (Stop)" / "Sell (Limit)" instead of       |
//|  "Buy Pending (Stop)" — cleaner fit inside the narrow bar.        |
//+------------------------------------------------------------------+

string ShortPreviewLabel(const TradePanelAction action, const double entry_price)
  {
   if(!IsPendingAction(action)) return ActionLabel(action);
   PendingSubtype st = DerivePendingSubtype(action, entry_price);
   string base = IsBuyAction(action) ? "Buy" : "Sell";
   return base + PendingSubtypeLabel(st);
  }

//+------------------------------------------------------------------+
//|  Price / volume helpers                                          |
//+------------------------------------------------------------------+

int PriceDigits()
  {
   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (d < 0) ? 5 : d;
  }

int VolumeDigits()
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) return 2;
   int d = 0;
   double v = step;
   while(v < 1.0 - 1e-9) { v *= 10.0; d++; }
   return d;
  }

double NormalizePriceValue(const double price)
  { return NormalizeDouble(price, PriceDigits()); }

double NormalizeVolumeValue(const double volume)
  {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(mn <= 0.0) mn = 0.01;
   if(mx <= 0.0) mx = 100.0;
   if(st <= 0.0) st = 0.01;
   double v = MathMax(mn, MathMin(mx, MathRound(volume / st) * st));
   return NormalizeDouble(v, VolumeDigits());
  }

string FormatLots(const double volume)
  { return DoubleToString(volume, VolumeDigits()); }

string FormatPrice(const double price)
  { return DoubleToString(price, PriceDigits()); }

string FormatPoints(const double points)
  { return DoubleToString(points, 0); }

string FormatMoney(const double value)
  { return DoubleToString(value, 2); }

string FormatPercent(const double value)
  { return DoubleToString(value, 2) + "%"; }

double CurrentReferencePrice(const bool is_buy)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return 0.0;
   return is_buy ? tick.ask : tick.bid;
  }

double CurrentMidPrice()
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return 0.0;
   return (tick.ask + tick.bid) * 0.5;
  }

bool ParseDoubleText(string text, double &value)
  {
   StringTrimLeft(text); StringTrimRight(text);
   if(StringLen(text) == 0) return false;
   value = StringToDouble(text);
   return true;
  }

//+------------------------------------------------------------------+
//|  SetStatus / EnsurePendingEntry                                  |
//+------------------------------------------------------------------+

void SetStatus(const string text, const bool sticky = false)
  {
   g_state.status_text = text;
   if(sticky) g_status_sticky = true;
   Print("[STATUS] ", text);
  }

void EnsurePendingEntry()
  {
   if(!IsPendingAction(g_state.action)) return;
   if(g_state.entry_price > 0.0) return;
   g_state.entry_price = CurrentReferencePrice(IsBuyAction(g_state.action));
  }

//+------------------------------------------------------------------+
//|  Save/restore scroll                                             |
//+------------------------------------------------------------------+

void SuppressChartScroll()
  {
   if(g_scroll_suppressed) return;
   g_scroll_was_enabled = (bool)ChartGetInteger(0, CHART_MOUSE_SCROLL);
   ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
   g_scroll_suppressed = true;
  }

void RestoreChartScroll()
  {
   if(!g_scroll_suppressed) return;
   ChartSetInteger(0, CHART_MOUSE_SCROLL, g_scroll_was_enabled);
   g_scroll_suppressed = false;
  }

void ResetDragState()
  {
   g_drag_phase     = DRAG_IDLE;
   g_drag_line_kind = "";
   g_drag_press_x   = 0;
   g_drag_press_y   = 0;
   RestoreChartScroll();
  }

//+------------------------------------------------------------------+
//|  DeletePreviewObjects / DeleteByPrefix                           |
//+------------------------------------------------------------------+

void DeletePreviewObjects()
  {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, PREV_PFX) == 0)
         ObjectDelete(0, n);
     }
   ResetDragState();
  }

void DeleteByPrefix()
  {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, PANEL_PREFIX) == 0)
         ObjectDelete(0, n);
     }
  }

//+------------------------------------------------------------------+
//|  ██  CLotForgePanel :: EVENT MAP                                  |
//|                                                                  |
//|  Uses standard CAppDialog EVENT_MAP macros.                      |
//|  ON_EVENT(event_type, control_member, handler_method)            |
//|  CAppDialog transforms raw CHARTEVENT_* into internal ON_CLICK,  |
//|  ON_END_EDIT etc. IDs before dispatching to OnEvent().           |
//+------------------------------------------------------------------+

EVENT_MAP_BEGIN(CLotForgePanel)
ON_EVENT(ON_CLICK, m_BtnRiskMode,     OnClickRiskMode)
ON_EVENT(ON_CLICK, m_BtnPrimaryUp,    OnClickPrimaryUp)
ON_EVENT(ON_CLICK, m_BtnPrimaryDn,    OnClickPrimaryDn)
ON_EVENT(ON_CLICK, m_BtnEntryUp,      OnClickEntryUp)
ON_EVENT(ON_CLICK, m_BtnEntryDn,      OnClickEntryDn)
ON_EVENT(ON_CLICK, m_BtnTPUp,         OnClickTPUp)
ON_EVENT(ON_CLICK, m_BtnTPDn,         OnClickTPDn)
ON_EVENT(ON_CLICK, m_BtnSLUp,         OnClickSLUp)
ON_EVENT(ON_CLICK, m_BtnSLDn,         OnClickSLDn)
ON_EVENT(ON_CLICK, m_BtnSell,         OnClickSell)
ON_EVENT(ON_CLICK, m_BtnBuy,          OnClickBuy)
ON_EVENT(ON_CLICK, m_BtnSellPending,  OnClickSellPending)
ON_EVENT(ON_CLICK, m_BtnBuyPending,   OnClickBuyPending)
ON_EVENT(ON_CLICK, m_BtnBE,           OnClickBE)
ON_EVENT(ON_CLICK, m_BtnTrailing,     OnClickTrailing)
ON_EVENT(ON_CLICK, m_ChkAutoBE,       OnClickAutoBE)
ON_EVENT(ON_CLICK, m_ChkAutoTrailing, OnClickAutoTrailing)
ON_EVENT(ON_CLICK, m_BtnAlgoTrading,  OnClickAlgoTrading)
ON_EVENT(ON_CLICK, m_BtnCancel,       OnClickCancel)
ON_EVENT(ON_CLICK, m_BtnSend,         OnClickSend)
ON_EVENT(ON_END_EDIT, m_EdtPrimary,   OnEndEditPrimary)
ON_EVENT(ON_END_EDIT, m_EdtEntry,     OnEndEditEntry)
ON_EVENT(ON_END_EDIT, m_EdtTP,        OnEndEditTP)
ON_EVENT(ON_END_EDIT, m_EdtSL,        OnEndEditSL)
EVENT_MAP_END(CAppDialog)

//+------------------------------------------------------------------+
//|  CLotForgePanel :: CreateInlineGroup                              |
//|  Creates: [Label LABEL_W][Edit EDIT_W][▲ SPIN_W][▼ SPIN_W]      |
//+------------------------------------------------------------------+

bool CLotForgePanel::CreateInlineGroup(const int x, const int y,
                                        CButton &lbl, const string lbl_text,
                                        CEdit &edt, const string edt_text,
                                        CButton &btn_up, CButton &btn_dn)
  {
   // Solid label block: white background, gray text — matches V1.07 style
   if(!lbl.Create(m_chart_id, m_name + "_lbl_" + lbl_text, m_subwin,
      x, y, x + LABEL_W, y + ROW_H)) return false;
   lbl.Text(lbl_text);
   lbl.FontSize(9);
   lbl.Color(C'110,110,110');      // ghosted gray text
   lbl.ColorBackground(clrWhite);  // solid white block
   if(!Add(lbl)) return false;

   int ex = x + LABEL_W;
   if(!edt.Create(m_chart_id, m_name + "_edt_" + lbl_text, m_subwin,
      ex, y, ex + EDIT_W, y + EDIT_H)) return false;
   edt.Text(edt_text);
   edt.FontSize(9);
   if(!Add(edt)) return false;

   int sx = ex + EDIT_W + 1;
   if(!btn_up.Create(m_chart_id, m_name + "_up_" + lbl_text, m_subwin,
      sx, y, sx + SPIN_W, y + SPIN_H)) return false;
   btn_up.Text("+");
   btn_up.FontSize(7);
   if(!Add(btn_up)) return false;

   if(!btn_dn.Create(m_chart_id, m_name + "_dn_" + lbl_text, m_subwin,
      sx, y + SPIN_H, sx + SPIN_W, y + ROW_H)) return false;
   btn_dn.Text("-");
   btn_dn.FontSize(7);
   if(!Add(btn_dn)) return false;

   return true;
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: CreateRiskModeGroup                            |
//|  Creates: [RiskMode btn][Edit][▲][▼]                             |
//+------------------------------------------------------------------+

bool CLotForgePanel::CreateRiskModeGroup(const int x, const int y)
  {
   string mode_text = (g_state.risk_mode == RISK_MODE_PERCENT) ? "Risk%" : "Lots";

   if(!m_BtnRiskMode.Create(m_chart_id, m_name + "_btn_riskmode", m_subwin,
      x, y, x + LABEL_W, y + ROW_H)) return false;
   m_BtnRiskMode.Text(mode_text);
   m_BtnRiskMode.FontSize(9);
   m_BtnRiskMode.ColorBackground(clrWhite);      // v1.07: flat label look, white like edit
   m_BtnRiskMode.Color(clrBlack);                // dark text on white
   if(!Add(m_BtnRiskMode)) return false;

   int ex = x + LABEL_W;
   string val_text = (g_state.risk_mode == RISK_MODE_PERCENT)
                     ? FormatPercent(g_state.risk_percent)
                     : FormatLots(g_state.lots);
   if(!m_EdtPrimary.Create(m_chart_id, m_name + "_edt_primary", m_subwin,
      ex, y, ex + EDIT_W, y + EDIT_H)) return false;
   m_EdtPrimary.Text(val_text);
   m_EdtPrimary.FontSize(9);
   if(!Add(m_EdtPrimary)) return false;

   int sx = ex + EDIT_W + 2;
   if(!m_BtnPrimaryUp.Create(m_chart_id, m_name + "_up_primary", m_subwin,
      sx, y, sx + SPIN_W, y + SPIN_H)) return false;
   m_BtnPrimaryUp.Text("+");
   m_BtnPrimaryUp.FontSize(7);
   if(!Add(m_BtnPrimaryUp)) return false;

   if(!m_BtnPrimaryDn.Create(m_chart_id, m_name + "_dn_primary", m_subwin,
      sx, y + SPIN_H, sx + SPIN_W, y + ROW_H)) return false;
   m_BtnPrimaryDn.Text("-");
   m_BtnPrimaryDn.FontSize(7);
   if(!Add(m_BtnPrimaryDn)) return false;

   return true;
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: CreatePanel                                    |
//|                                                                  |
//|  Compact two-column layout:                                      |
//|  Row 1: [Lots/Risk%][val][±]  [Entry][val][±]                   |
//|  Row 2: [TP][val][±]          [SL][val][±]                       |
//|  Row 3: [Sell]                [Buy]                              |
//|  Row 4: [Sell Pending]        [Buy Pending]                      |
//|  Row 5: [BE ■amber]           [Trailing ■purple]                 |
//|  Row 6: [☐ Auto BE]          [☐ Auto Trailing]  (checkboxes)    |
//|  Row 7: [Cancel]              [Send]             (always last)   |
//+------------------------------------------------------------------+

bool CLotForgePanel::CreatePanel(const long chart, const string name,
                                  const int subwin, const int x1, const int y1)
  {
   int x2 = x1 + PANEL_W;
   int y2 = y1 + PANEL_H;
   if(!CAppDialog::Create(chart, name, subwin, x1, y1, x2, y2))
      return false;

   // Compute layout metrics from the REAL client area reported by CAppDialog.
   // CAppDialog's chrome (outer frame + title bar border insets) makes the
   // usable client narrower than PANEL_W.  Using ClientAreaWidth() here is
   // the correct approach — it reflects the actual drawable rectangle so the
   // right column never gets clipped regardless of DPI or border thickness.
   m_content_w = ClientAreaWidth() - 6;   // 3px margin each side inside client area
   m_col_w     = (m_content_w - COL_GAP) / 2;

   int cx = 3;
   int cy = 2;

   // ── Row 1: RiskMode group + Entry group ────────────────────────
   if(!CreateRiskModeGroup(cx, cy)) return false;
   int rx = cx + m_col_w + COL_GAP;
   if(!CreateInlineGroup(rx, cy,
         m_LblEntry, "Entry",
         m_EdtEntry, g_state.entry_price <= 0.0 ? "0" : FormatPrice(g_state.entry_price),
         m_BtnEntryUp, m_BtnEntryDn)) return false;
   cy += ROW_H + ROW_GAP;

   // ── Row 2: TP group + SL group ─────────────────────────────────
   if(!CreateInlineGroup(cx, cy,
         m_LblTP, "TP",
         m_EdtTP, FormatPoints(g_state.tp_points),
         m_BtnTPUp, m_BtnTPDn)) return false;
   if(!CreateInlineGroup(rx, cy,
         m_LblSL, "SL",
         m_EdtSL, FormatPoints(g_state.sl_points),
         m_BtnSLUp, m_BtnSLDn)) return false;
   cy += ROW_H + SECTION_GAP;

   // ── Comment ────────────────────────────────────────────────────
   // ── Action buttons: 2-column grid ──────────────────────────────
   int btn_w = (m_content_w - 4) / 2;

   if(!m_BtnSell.Create(chart, name + "_btn_sell", subwin,
      cx, cy, cx + btn_w, cy + ACTION_BTN_H)) return false;
   m_BtnSell.Text("Sell");
   m_BtnSell.ColorBackground(CLR_SELL_BG);
   m_BtnSell.Color(clrWhite);
   m_BtnSell.ColorBorder(C'210,50,40');
   if(!Add(m_BtnSell)) return false;

   if(!m_BtnBuy.Create(chart, name + "_btn_buy", subwin,
      cx + btn_w + 4, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
   m_BtnBuy.Text("Buy");
   m_BtnBuy.ColorBackground(CLR_BUY_BG);
   m_BtnBuy.Color(clrWhite);
   m_BtnBuy.ColorBorder(C'0,180,0');
   if(!Add(m_BtnBuy)) return false;
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   if(!m_BtnSellPending.Create(chart, name + "_btn_sellp", subwin,
      cx, cy, cx + btn_w, cy + ACTION_BTN_H)) return false;
   m_BtnSellPending.Text("Sell Pending");
   m_BtnSellPending.ColorBackground(CLR_SELL_BG);
   m_BtnSellPending.Color(clrWhite);
   m_BtnSellPending.ColorBorder(C'210,50,40');
   if(!Add(m_BtnSellPending)) return false;

   if(!m_BtnBuyPending.Create(chart, name + "_btn_buyp", subwin,
      cx + btn_w + 4, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
   m_BtnBuyPending.Text("Buy Pending");
   m_BtnBuyPending.ColorBackground(CLR_BUY_BG);
   m_BtnBuyPending.Color(clrWhite);
   m_BtnBuyPending.ColorBorder(C'0,180,0');
   if(!Add(m_BtnBuyPending)) return false;
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   // ── Row: BE | Trailing ─────────────────────────────────────────
   //  BE is amber, Trailing is purple — visually distinct from trade-side buttons
   if(!m_BtnBE.Create(chart, name + "_btn_be", subwin,
      cx, cy, cx + btn_w, cy + ACTION_BTN_H)) return false;
   m_BtnBE.Text("BE");
   m_BtnBE.ColorBackground(CLR_BE_BG);
   m_BtnBE.Color(clrWhite);
   m_BtnBE.ColorBorder(CLR_BE_BORDER);
   if(!Add(m_BtnBE)) return false;

   if(!m_BtnTrailing.Create(chart, name + "_btn_trail", subwin,
      cx + btn_w + 4, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
   m_BtnTrailing.Text("Trailing");
   m_BtnTrailing.ColorBackground(CLR_TRAILING_BG);
   m_BtnTrailing.Color(clrWhite);
   m_BtnTrailing.ColorBorder(CLR_TRAILING_BORDER);
   if(!Add(m_BtnTrailing)) return false;
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   // ── Row: Auto BE | Auto Trailing (real toggle checkboxes) ──────
   //  CButton styled as checkbox: text shows [ ] / [✓], bg shows off/on color
   string chk_be_text   = g_state.break_even_enabled    ? "[✓] Auto BE"      : "[ ] Auto BE";
   string chk_trail_text= g_state.trailing_stop_enabled ? "[✓] Auto Trailing" : "[ ] Auto Trailing";

   // ── Row: Auto BE | Auto Trailing ─────────────────────────────
   //  v1.09: promoted to ACTION_BTN_H (28) for visual height consistency
   if(!m_ChkAutoBE.Create(chart, name + "_chk_autobe", subwin,
      cx, cy, cx + btn_w, cy + ACTION_BTN_H)) return false;
   m_ChkAutoBE.Text(chk_be_text);
   m_ChkAutoBE.FontSize(8);
   m_ChkAutoBE.ColorBackground(g_state.break_even_enabled ? CLR_CHK_ON_BG : CLR_CHK_OFF_BG);
   m_ChkAutoBE.Color(g_state.break_even_enabled ? clrWhite : clrBlack);
   m_ChkAutoBE.ColorBorder(C'130,140,160');
   if(!Add(m_ChkAutoBE)) return false;

   if(!m_ChkAutoTrailing.Create(chart, name + "_chk_autotrail", subwin,
      cx + btn_w + 4, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
   m_ChkAutoTrailing.Text(chk_trail_text);
   m_ChkAutoTrailing.FontSize(8);
   m_ChkAutoTrailing.ColorBackground(g_state.trailing_stop_enabled ? CLR_CHK_ON_BG : CLR_CHK_OFF_BG);
   m_ChkAutoTrailing.Color(g_state.trailing_stop_enabled ? clrWhite : clrBlack);
   m_ChkAutoTrailing.ColorBorder(C'130,140,160');
   if(!Add(m_ChkAutoTrailing)) return false;
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   // ── Row: Algo Trading (full-width toggle row — same family as Auto BE/Trailing)
   {
    string algo_text = g_state.algo_trading_ui_enabled ? "[✓] Algo Trading" : "[ ] Algo Trading";
    if(!m_BtnAlgoTrading.Create(chart, name + "_btn_algo", subwin,
       cx, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
    m_BtnAlgoTrading.Text(algo_text);
    m_BtnAlgoTrading.FontSize(9);
    m_BtnAlgoTrading.ColorBackground(g_state.algo_trading_ui_enabled ? CLR_CHK_ON_BG : CLR_CHK_OFF_BG);
    m_BtnAlgoTrading.Color(g_state.algo_trading_ui_enabled ? clrWhite : clrBlack);
    m_BtnAlgoTrading.ColorBorder(C'130,140,160');
    if(!Add(m_BtnAlgoTrading)) return false;
   }
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   // ── Row: Cancel | Send (always the final row) ──────────────────
   if(!m_BtnCancel.Create(chart, name + "_btn_cancel", subwin,
      cx, cy, cx + btn_w, cy + ACTION_BTN_H)) return false;
   m_BtnCancel.Text("Cancel");
   m_BtnCancel.ColorBackground(CLR_NEUTRAL_BG);
   m_BtnCancel.Color(clrBlack);
   if(!Add(m_BtnCancel)) return false;

   if(!m_BtnSend.Create(chart, name + "_btn_send", subwin,
      cx + btn_w + 4, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
   m_BtnSend.Text("Send");
   m_BtnSend.ColorBackground(CLR_NEUTRAL_BG);
   m_BtnSend.Color(clrBlack);
   if(!Add(m_BtnSend)) return false;


   // ── Apply two-blue chrome AFTER all controls are added ─────────
   //  CAppDialog caption (title bar) is OBJ_EDIT named <n>Caption —
   //  not OBJ_RECTANGLE_LABEL. Colors applied here (post-Add) are
   //  safe from being reset by subsequent Add() calls.
   //    OBJ_RECTANGLE_LABEL <n>ClientBack → inner body (lighter blue)
   //    OBJ_RECTANGLE_LABEL <n>*          → outer frame (dark blue)
   //    OBJ_EDIT            <n>Caption    → title bar text strip (dark blue)
   //    OBJ_BUTTON          <n>Min/Close/Back → window controls (gray)
   {
    string dlg_n  = Name();
    int    n_objs = ObjectsTotal(chart, subwin, -1);
    for(int k = 0; k < n_objs; k++)
      {
       string      obj_n = ObjectName(chart, k, subwin, -1);
       if(StringFind(obj_n, dlg_n) != 0) continue;
       string      sfx   = StringSubstr(obj_n, StringLen(dlg_n));
       ENUM_OBJECT otype = (ENUM_OBJECT)ObjectGetInteger(chart, obj_n, OBJPROP_TYPE);

       if(otype == OBJ_RECTANGLE_LABEL)
         {
          if(sfx == "ClientBack")
            {
             ObjectSetInteger(chart, obj_n, OBJPROP_BGCOLOR, CLR_PANEL_BG);
             ObjectSetInteger(chart, obj_n, OBJPROP_COLOR,   CLR_PANEL_BG);
            }
          else
            {
             ObjectSetInteger(chart, obj_n, OBJPROP_BGCOLOR, CLR_TITLE_BG);
             ObjectSetInteger(chart, obj_n, OBJPROP_COLOR,   CLR_TITLE_BG);
            }
         }
       else if(otype == OBJ_EDIT)
         {
          // Caption bar (OBJ_EDIT) — dark blue background, white text
          if(sfx == "Caption")
            {
             ObjectSetInteger(chart, obj_n, OBJPROP_BGCOLOR,      CLR_TITLE_BG);
             ObjectSetInteger(chart, obj_n, OBJPROP_BORDER_COLOR, CLR_TITLE_BG);
             ObjectSetInteger(chart, obj_n, OBJPROP_COLOR,        clrWhite);
            }
         }
       else if(otype == OBJ_BUTTON)
         {
          if(sfx == "Min" || sfx == "Close" || sfx == "Back")
            {
             ObjectSetInteger(chart, obj_n, OBJPROP_BGCOLOR, CLR_TITLE_BTN);
             ObjectSetInteger(chart, obj_n, OBJPROP_COLOR,   clrBlack);
            }
         }
      }
   }

   return true;
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: RefreshValues                                  |
//+------------------------------------------------------------------+

void CLotForgePanel::RefreshValues(void)
  {
   string prim_text = (g_state.risk_mode == RISK_MODE_PERCENT)
                      ? FormatPercent(g_state.risk_percent)
                      : FormatLots(g_state.lots);
   if(m_EdtPrimary.Text() != prim_text) m_EdtPrimary.Text(prim_text);

   string entry_text = g_state.entry_price <= 0.0 ? "0" : FormatPrice(g_state.entry_price);
   if(m_EdtEntry.Text() != entry_text) m_EdtEntry.Text(entry_text);

   string tp_text = FormatPoints(g_state.tp_points);
   if(m_EdtTP.Text() != tp_text) m_EdtTP.Text(tp_text);

   string sl_text = FormatPoints(g_state.sl_points);
   if(m_EdtSL.Text() != sl_text) m_EdtSL.Text(sl_text);

  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: ApplyActionStyle / RefreshActionButtons        |
//+------------------------------------------------------------------+

void CLotForgePanel::ApplyActionStyle(CButton &btn, const color base_clr, const bool selected)
  {
   btn.ColorBackground(base_clr);
   btn.ColorBorder(selected ? CLR_SELECTED_BORDER : base_clr);
  }

void CLotForgePanel::RefreshActionButtons(void)
  {
   ApplyActionStyle(m_BtnSell,        CLR_SELL_BG, g_state.action == ACTION_SELL);
   ApplyActionStyle(m_BtnBuy,         CLR_BUY_BG,  g_state.action == ACTION_BUY);
   ApplyActionStyle(m_BtnSellPending, CLR_SELL_BG, g_state.action == ACTION_SELL_PENDING);
   ApplyActionStyle(m_BtnBuyPending,  CLR_BUY_BG,  g_state.action == ACTION_BUY_PENDING);

   color cs = (g_state.action != ACTION_NONE) ? C'180,190,208' : CLR_NEUTRAL_BG;
   ApplyActionStyle(m_BtnCancel, cs, false);
   ApplyActionStyle(m_BtnSend,   cs, false);

   RefreshBETrailingButtons();
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: RefreshBETrailingButtons                       |
//|  Updates Auto BE / Auto Trailing checkbox appearance to reflect   |
//|  current g_state.break_even_enabled / trailing_stop_enabled.     |
//+------------------------------------------------------------------+

void CLotForgePanel::RefreshBETrailingButtons(void)
  {
   // Auto BE checkbox
   bool be_on = g_state.break_even_enabled;
   m_ChkAutoBE.Text(be_on ? "[✓] Auto BE" : "[ ] Auto BE");
   m_ChkAutoBE.ColorBackground(be_on ? CLR_CHK_ON_BG : CLR_CHK_OFF_BG);
   m_ChkAutoBE.Color(be_on ? clrWhite : clrBlack);

   // Auto Trailing checkbox
   bool trail_on = g_state.trailing_stop_enabled;
   m_ChkAutoTrailing.Text(trail_on ? "[✓] Auto Trailing" : "[ ] Auto Trailing");
   m_ChkAutoTrailing.ColorBackground(trail_on ? CLR_CHK_ON_BG : CLR_CHK_OFF_BG);
   m_ChkAutoTrailing.Color(trail_on ? clrWhite : clrBlack);

   // Algo Trading toggle row
   bool algo_on = g_state.algo_trading_ui_enabled;
   m_BtnAlgoTrading.Text(algo_on ? "[✓] Algo Trading" : "[ ] Algo Trading");
   m_BtnAlgoTrading.ColorBackground(algo_on ? CLR_CHK_ON_BG : CLR_CHK_OFF_BG);
   m_BtnAlgoTrading.Color(algo_on ? clrWhite : clrBlack);
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: IsMouseOverPanel                               |
//+------------------------------------------------------------------+

bool CLotForgePanel::IsMouseOverPanel(const int mx, const int my)
  {
   int x1 = (int)Left();
   int y1 = (int)Top();
   int x2 = (int)Right();
   int y2 = (int)Bottom();
   return (mx >= x1 && mx <= x2 && my >= y1 && my <= y2);
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: Event Handlers                                |
//+------------------------------------------------------------------+

void CLotForgePanel::OnClickRiskMode(void)
  {
   g_state.risk_mode = (g_state.risk_mode == RISK_MODE_LOTS)
                       ? RISK_MODE_PERCENT : RISK_MODE_LOTS;
   m_BtnRiskMode.Text(g_state.risk_mode == RISK_MODE_PERCENT ? "Risk%" : "Lots");
   RefreshValues();
   UpdatePreview();
   ChartRedraw(0);
  }

void CLotForgePanel::OnClickPrimaryUp(void)
  {
   if(g_state.risk_mode == RISK_MODE_PERCENT)
     { g_state.risk_percent = NormalizeDouble(g_state.risk_percent + 0.25, 2); }
   else
     { AdjustLots(+1); }
   RefreshValues(); UpdatePreview(); ChartRedraw(0);
  }

void CLotForgePanel::OnClickPrimaryDn(void)
  {
   if(g_state.risk_mode == RISK_MODE_PERCENT)
     { g_state.risk_percent = MathMax(0.0, NormalizeDouble(g_state.risk_percent - 0.25, 2)); }
   else
     { AdjustLots(-1); }
   RefreshValues(); UpdatePreview(); ChartRedraw(0);
  }

void CLotForgePanel::OnClickEntryUp(void)
  { AdjustEntry(+1); UpdatePreview(); }

void CLotForgePanel::OnClickEntryDn(void)
  { AdjustEntry(-1); UpdatePreview(); }

void CLotForgePanel::OnClickTPUp(void)
  { AdjustDistance(g_state.tp_points, +1); RefreshValues(); UpdatePreview(); ChartRedraw(0); }

void CLotForgePanel::OnClickTPDn(void)
  { AdjustDistance(g_state.tp_points, -1); RefreshValues(); UpdatePreview(); ChartRedraw(0); }

void CLotForgePanel::OnClickSLUp(void)
  { AdjustDistance(g_state.sl_points, +1); RefreshValues(); UpdatePreview(); ChartRedraw(0); }

void CLotForgePanel::OnClickSLDn(void)
  { AdjustDistance(g_state.sl_points, -1); RefreshValues(); UpdatePreview(); ChartRedraw(0); }

void CLotForgePanel::OnClickSell(void)
  { HandleOrderSelection(ACTION_SELL); }

void CLotForgePanel::OnClickBuy(void)
  { HandleOrderSelection(ACTION_BUY); }

void CLotForgePanel::OnClickSellPending(void)
  { HandleOrderSelection(ACTION_SELL_PENDING); }

void CLotForgePanel::OnClickBuyPending(void)
  { HandleOrderSelection(ACTION_BUY_PENDING); }

void CLotForgePanel::OnClickCancel(void)
  {
   g_state.action      = ACTION_NONE;
   g_state.entry_price = 0.0;
   g_state.active_edit = EDIT_TARGET_NONE;
   g_status_sticky     = false;
   RefreshActionButtons();
   RefreshValues();
   DeletePreviewObjects();
   SetStatus("Cancelado. Selecione o tipo de ordem.");
   ChartRedraw(0);
  }

void CLotForgePanel::OnClickSend(void)
  {
   // Read current edit values from panel
   double val;
   string text;
   
   text = m_EdtPrimary.Text();
   if(ParseDoubleText(text, val))
     {
      if(g_state.risk_mode == RISK_MODE_PERCENT)
         g_state.risk_percent = MathMax(0.0, val);
      else
         g_state.lots = NormalizeVolumeValue(val);
     }
   text = m_EdtEntry.Text();
   if(ParseDoubleText(text, val))
      g_state.entry_price = (val <= 0.0) ? 0.0 : NormalizePriceValue(val);
   text = m_EdtTP.Text();
   if(ParseDoubleText(text, val))
      g_state.tp_points = MathMax(0.0, MathRound(val));
   text = m_EdtSL.Text();
   if(ParseDoubleText(text, val))
      g_state.sl_points = MathMax(0.0, MathRound(val));
   TradeParams plan;
   string build_reason;
   string validation_msg;

   bool built = BuildTradePlan(plan, build_reason);
   if(!built)
     { SetStatus(build_reason != "" ? build_reason : "Erro: plano inválido.", true); ChartRedraw(0); return; }

   bool valid_plan = ValidateTradeRequest(plan, validation_msg);
   if(!valid_plan)
     { SetStatus(validation_msg, true); ChartRedraw(0); return; }

   SendSelectedOrder(plan);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: OnClickBE                                      |
//|  BE manual: move SL para entrada + offset de proteção.            |
//|  Filtra por símbolo atual e magic do EA.                          |
//+------------------------------------------------------------------+

void CLotForgePanel::OnClickBE(void)
  {
   bool found = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagicNumber && magic != 0) continue;

      found = true;
      if(TryManualBreakEven(t))
        {
         ChartRedraw(0);
         return;
        }
      // TryManualBreakEven already set status — just redraw
      ChartRedraw(0);
      return;
     }
   if(!found)
      SetStatus("Nenhuma posição gerenciável aberta no símbolo atual.", true);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: OnClickTrailing                                |
//|  Arma o trailing na posição atual do símbolo.                     |
//|  O trailing só atua efetivamente quando o BE estiver ativo.       |
//+------------------------------------------------------------------+

void CLotForgePanel::OnClickTrailing(void)
  {
   bool found = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagicNumber && magic != 0) continue;
      found = true;

      // Garantir que o ticket esteja no estado gerenciado
      EnsureManagedState(t);

      // Armar trailing no estado do ticket
      int idx = FindManagedIndex(t);
      if(idx >= 0)
        {
         g_managed_trades[idx].trailing_armed = true;
         if(InpTrailingRequiresBE && !g_managed_trades[idx].be_applied)
            SetStatus("Trailing armado. Aguardando BE ativo para atuar.", true);
         else
            SetStatus("Trailing armado e ativo.", true);
        }
      break;
     }
   if(!found)
      SetStatus("Nenhuma posição gerenciável aberta no símbolo atual.", true);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: OnClickAutoBE                                  |
//|  Toggles g_state.break_even_enabled and refreshes checkbox UI.   |
//+------------------------------------------------------------------+

void CLotForgePanel::OnClickAutoBE(void)
  {
   g_state.break_even_enabled = !g_state.break_even_enabled;
   RefreshBETrailingButtons();
   string msg = g_state.break_even_enabled
                ? "Auto BE ativado."
                : "Auto BE desativado.";
   SetStatus(msg);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: OnClickAutoTrailing                            |
//|  Toggles g_state.trailing_stop_enabled and refreshes checkbox.   |
//+------------------------------------------------------------------+

void CLotForgePanel::OnClickAutoTrailing(void)
  {
   g_state.trailing_stop_enabled = !g_state.trailing_stop_enabled;
   RefreshBETrailingButtons();

   if(g_state.trailing_stop_enabled)
     {
      // Armar trailing em todas as posições gerenciáveis já abertas
      int armed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(!PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic != InpMagicNumber && magic != 0) continue;
         EnsureManagedState(t);
         int idx = FindManagedIndex(t);
         if(idx >= 0)
           {
            // Sincronizar proteção real antes de armar
            SyncProtectionState(idx);
            g_managed_trades[idx].trailing_armed = true;
            armed++;
           }
        }
      if(armed > 0)
         SetStatus(StringFormat("Auto Trailing ativado — %d posição(ões) armada(s).", armed));
      else
         SetStatus("Auto Trailing ativado.");
     }
   else
     {
      SetStatus("Auto Trailing desativado.");
     }
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: OnClickAlgoTrading                             |
//|  Toggle do Algo Trading — ativa/desativa pipeline completo de     |
//|  gestão automática: Auto BE → Parcial → Trailing pós-BE.          |
//+------------------------------------------------------------------+

void CLotForgePanel::OnClickAlgoTrading(void)
  {
   // Verificar pré-condições de trading antes de ativar
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
     {
      SetStatus("Terminal desconectado.", true);
      ChartRedraw(0);
      return;
     }

   bool term_allowed = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool ea_allowed   = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);

   // Toggle estado lógico
   g_algo_trading_enabled            = !g_algo_trading_enabled;
   g_state.algo_trading_ui_enabled   = g_algo_trading_enabled;
   RefreshBETrailingButtons();

   if(!g_algo_trading_enabled)
     {
      SetStatus("Algo Trading desativado.", true);
      ChartRedraw(0);
      return;
     }

   // Ao ativar: verificar permissões reais
   if(!term_allowed)
     {
      SetStatus("Algo Trading ativado — mas AutoTrading está DESLIGADO no terminal!", true);
     }
   else if(!ea_allowed)
     {
      SetStatus("Algo Trading ativado — mas EA sem permissão de trade (verifique propriedades).", true);
     }
   else
     {
      // Marcar posições abertas atuais como algo_managed = true
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(!PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic != InpMagicNumber && magic != 0) continue;
         EnsureManagedState(t);
         int idx = FindManagedIndex(t);
         if(idx >= 0)
           {
            g_managed_trades[idx].algo_managed    = true;
            g_managed_trades[idx].trailing_armed  = true;
            count++;
           }
        }
      if(count > 0)
         SetStatus(StringFormat("Algo Trading ON — %d posição(ões) no pipeline (BE→Parcial→Trailing).", count), true);
      else
         SetStatus("Algo Trading ON — aguardando próxima posição.", true);
     }

   Print("[ALGO] g_algo_trading_enabled=", g_algo_trading_enabled,
         "  TERMINAL_TRADE_ALLOWED=", term_allowed,
         "  MQL_TRADE_ALLOWED=", ea_allowed);
   ChartRedraw(0);
  }

void CLotForgePanel::OnEndEditPrimary(void)
  {
   double val;
   string text = m_EdtPrimary.Text();
   if(ParseDoubleText(text, val))
     {
      if(g_state.risk_mode == RISK_MODE_PERCENT)
         g_state.risk_percent = MathMax(0.0, val);
      else
         g_state.lots = NormalizeVolumeValue(val);
     }
   RefreshValues(); UpdatePreview();
  }

void CLotForgePanel::OnEndEditEntry(void)
  {
   double val;
   if(ParseDoubleText(m_EdtEntry.Text(), val))
      g_state.entry_price = (val <= 0.0) ? 0.0 : NormalizePriceValue(val);
   RefreshValues(); UpdatePreview();
  }

void CLotForgePanel::OnEndEditTP(void)
  {
   double val;
   if(ParseDoubleText(m_EdtTP.Text(), val))
      g_state.tp_points = MathMax(0.0, MathRound(val));
   RefreshValues(); UpdatePreview();
  }

void CLotForgePanel::OnEndEditSL(void)
  {
   double val;
   if(ParseDoubleText(m_EdtSL.Text(), val))
      g_state.sl_points = MathMax(0.0, MathRound(val));
   RefreshValues(); UpdatePreview();
  }


//+------------------------------------------------------------------+
//|  HandleOrderSelection (free function — uses g_panel)             |
//+------------------------------------------------------------------+

void HandleOrderSelection(const TradePanelAction action)
  {
   g_status_sticky = false;
   g_state.action = action;
   if(IsMarketAction(action))      g_state.entry_price = 0.0;
   else if(IsPendingAction(action)) EnsurePendingEntry();
   g_panel.RefreshActionButtons();
   g_panel.RefreshValues();
   string lbl = EffectiveActionLabel(action, g_state.entry_price);
   SetStatus("Ação: " + lbl + ". Configure e clique Send.");
   UpdatePreview();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//|  ██  FASE 4A — Planning & Validation Layer                       |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|  CalcLotsFromRiskPercent                                         |
//|                                                                  |
//|  Derives position size from account risk %.                      |
//|  Formula: lots = RiskMoney * TickSize / (SLDist * TickValue)     |
//|  where SLDist = MathAbs(entry_price - sl_price) in price units.  |
//|                                                                  |
//|  Returns false (with out_lots = 0) on any invalid input or       |
//|  data unavailability — no silent fallbacks.                      |
//+------------------------------------------------------------------+

bool CalcLotsFromRiskPercent(const double entry_price, const double sl_price,
                             const bool is_buy, double &out_lots, string &out_reason)
  {
   out_lots   = 0.0;
   out_reason = "";

   // ── Sanity: prices must be positive and distinct ─────────────────
   if(entry_price <= 0.0 || sl_price <= 0.0)
     { out_reason = "Erro: preço de entrada ou SL inválido para cálculo de lote."; return false; }

   double sl_dist = MathAbs(entry_price - sl_price);
   if(sl_dist < _Point * 0.5)
     { out_reason = "Erro: SL inválido para calcular lote por risco."; return false; }

   // ── Semantic sanity: SL must be on the correct side ──────────────
   if(is_buy  && sl_price >= entry_price)
     { out_reason = "Erro: SL de compra deve estar abaixo da entrada."; return false; }
   if(!is_buy && sl_price <= entry_price)
     { out_reason = "Erro: SL de venda deve estar acima da entrada."; return false; }

   // ── Symbol economics ──────────────────────────────────────────────
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0)
     { out_reason = "Erro: dados de tick do símbolo indisponíveis."; return false; }

   // ── Account base ─────────────────────────────────────────────────
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0)
     { out_reason = "Erro: saldo da conta indisponível."; return false; }
   double risk_money = balance * g_state.risk_percent / 100.0;
   if(risk_money <= 0.0)
     { out_reason = "Erro: percentual de risco resulta em valor zero."; return false; }

   // ── Core formula ──────────────────────────────────────────────────
   // loss per lot = (sl_dist / tick_size) * tick_value
   double loss_per_lot = sl_dist / tick_size * tick_value;
   if(loss_per_lot <= 0.0)
     { out_reason = "Erro: custo por lote calculado como zero."; return false; }

   double raw_lots = risk_money / loss_per_lot;

   // ── Normalize to broker constraints ───────────────────────────────
   double vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vol_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vol_min  <= 0.0) vol_min  = 0.01;
   if(vol_max  <= 0.0) vol_max  = 100.0;
   if(vol_step <= 0.0) vol_step = 0.01;

   // Floor to step boundary (conservative — do not exceed risk target)
   double steps     = MathFloor(raw_lots / vol_step);
   double norm_lots = NormalizeDouble(steps * vol_step, VolumeDigits());

   // ── Below broker minimum → fail cleanly; do NOT promote upward ───
   // Clamping up to vol_min would silently increase the trader's risk.
   if(norm_lots < vol_min)
     {
      out_reason = StringFormat(
         "Erro: risco muito baixo para o lote mínimo do símbolo (calculado %s, mínimo %s).",
         FormatLots(norm_lots), FormatLots(vol_min));
      return false;
     }

   // Cap downward at vol_max (conservative — never exceed broker cap)
   if(norm_lots > vol_max) norm_lots = NormalizeDouble(vol_max, VolumeDigits());

   out_lots = norm_lots;
   return (out_lots > 0.0);
  }

//+------------------------------------------------------------------+
//|  BuildTradePlan                                                  |
//|                                                                  |
//|  Builds a complete TradeParams from current g_state.             |
//|  Centralises all derivation: entry, SL, TP, lots, money, RR.    |
//|  Does NOT validate — call ValidateTradeRequest afterwards.       |
//+------------------------------------------------------------------+

bool BuildTradePlan(TradeParams &params, string &out_reason)
  {
   params.Clear();
   out_reason = "";

   if(g_state.action == ACTION_NONE)
     { out_reason = "Nenhuma ação selecionada."; return false; }

   bool is_buy    = IsBuyAction(g_state.action);
   bool is_market = IsMarketAction(g_state.action);

   // ── 1. Effective entry price ──────────────────────────────────────
   double entry;
   if(is_market)
      entry = CurrentReferencePrice(is_buy);
   else
      entry = g_state.entry_price;

   if(entry <= 0.0)
     { out_reason = "Preço de entrada indisponível."; return false; }
   params.entry_price = NormalizePriceValue(entry);

   // ── 2. SL / TP prices from distance points ────────────────────────
   double sl_pts = g_state.sl_points;
   double tp_pts = g_state.tp_points;

   params.sl_points = sl_pts;
   params.tp_points = tp_pts;

   if(is_buy)
     {
      params.sl_price = NormalizePriceValue(params.entry_price - sl_pts * _Point);
      params.tp_price = (tp_pts > 0.0)
                        ? NormalizePriceValue(params.entry_price + tp_pts * _Point)
                        : 0.0;
     }
   else
     {
      params.sl_price = NormalizePriceValue(params.entry_price + sl_pts * _Point);
      params.tp_price = (tp_pts > 0.0)
                        ? NormalizePriceValue(params.entry_price - tp_pts * _Point)
                        : 0.0;
     }

   // ── 3. Lots ───────────────────────────────────────────────────────
   if(g_state.risk_mode == RISK_MODE_PERCENT)
     {
      double calc_lots;
      string calc_reason;
      if(!CalcLotsFromRiskPercent(params.entry_price, params.sl_price,
                                  is_buy, calc_lots, calc_reason))
        { out_reason = calc_reason; return false; }
      params.lots     = calc_lots;
      params.risk_pct = g_state.risk_percent;
     }
   else
     {
      params.lots     = g_state.lots;
      params.risk_pct = 0.0;
     }

   if(params.lots <= 0.0)
     { out_reason = "Lotes inválidos."; return false; }

   // ── 4. R:R ratio ─────────────────────────────────────────────────
   params.rr_ratio = (sl_pts > 0.0 && tp_pts > 0.0)
                     ? NormalizeDouble(tp_pts / sl_pts, 2)
                     : 0.0;

   // ── 5. Risk / Reward money ────────────────────────────────────────
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size > 0.0 && tick_value > 0.0 && sl_pts > 0.0)
     {
      double sl_dist = MathAbs(params.entry_price - params.sl_price);
      params.risk_money = NormalizeDouble(sl_dist / tick_size * tick_value * params.lots, 2);

      if(tp_pts > 0.0)
        {
         double tp_dist = MathAbs(params.tp_price - params.entry_price);
         params.reward_money = NormalizeDouble(tp_dist / tick_size * tick_value * params.lots, 2);
        }

      if(g_state.risk_mode == RISK_MODE_LOTS)
        {
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         if(balance > 0.0)
           {
            params.risk_pct    = NormalizeDouble(params.risk_money   / balance * 100.0, 2);
            params.reward_pct  = NormalizeDouble(params.reward_money / balance * 100.0, 2);
           }
        }
      else
        {
         // risk-% mode: balance already known — derive reward_pct from reward_money
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         if(balance > 0.0 && params.reward_money > 0.0)
            params.reward_pct = NormalizeDouble(params.reward_money / balance * 100.0, 2);
        }
     }

   return true;
  }

//+------------------------------------------------------------------+
//|  ValidateTradeRequest                                            |
//|                                                                  |
//|  Validates a built TradeParams against symbol and semantic rules.|
//|  Returns true + ready message, or false + first blocking reason. |
//+------------------------------------------------------------------+

bool ValidateTradeRequest(const TradeParams &params, string &message)
  {
   message = "";

   // ── 1. Action selected ────────────────────────────────────────────
   if(g_state.action == ACTION_NONE)
     { message = "Erro: nenhuma ação selecionada."; return false; }

   bool is_buy    = IsBuyAction(g_state.action);
   bool is_market = IsMarketAction(g_state.action);

   // ── 2. Entry price ────────────────────────────────────────────────
   if(params.entry_price <= 0.0)
     { message = "Erro: preço de entrada inválido."; return false; }

   // Pending requires a user-defined entry
   if(IsPendingAction(g_state.action) && g_state.entry_price <= 0.0)
     { message = "Erro: entrada pendente não definida."; return false; }

   // ── 3. SL must be set and non-zero ────────────────────────────────
   if(params.sl_points <= 0.0)
     { message = "Erro: distância de SL deve ser > 0."; return false; }
   if(params.sl_price <= 0.0)
     { message = "Erro: preço de SL inválido."; return false; }

   // ── 4. Semantic: SL on correct side of entry ──────────────────────
   if(is_buy && params.sl_price >= params.entry_price)
     { message = "Erro: SL de compra deve estar abaixo da entrada."; return false; }
   if(!is_buy && params.sl_price <= params.entry_price)
     { message = "Erro: SL de venda deve estar acima da entrada."; return false; }

   // ── 5. TP semantic (only if TP is set) ───────────────────────────
   if(params.tp_points > 0.0 && params.tp_price > 0.0)
     {
      if(is_buy && params.tp_price <= params.entry_price)
        { message = "Erro: TP de compra deve estar acima da entrada."; return false; }
      if(!is_buy && params.tp_price >= params.entry_price)
        { message = "Erro: TP de venda deve estar abaixo da entrada."; return false; }
     }

   // ── 6. Lots ───────────────────────────────────────────────────────
   if(params.lots <= 0.0)
     { message = "Erro: lotes devem ser > 0."; return false; }

   double vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vol_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(vol_min > 0.0 && params.lots < vol_min)
     { message = StringFormat("Erro: lotes %.5f abaixo do mínimo %.5f.", params.lots, vol_min); return false; }
   if(vol_max > 0.0 && params.lots > vol_max)
     { message = StringFormat("Erro: lotes %.5f acima do máximo %.5f.", params.lots, vol_max); return false; }

   // ── 7. Stops-level distance ───────────────────────────────────────
   // SYMBOL_TRADE_STOPS_LEVEL is in points (integer).
   int stops_level_pts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stops_level_pts > 0)
     {
      double min_dist = stops_level_pts * _Point;

      // For market orders the reference is current bid/ask.
      // For pending orders the reference is the entry price itself.
      // We check SL distance from entry (always required):
      double sl_dist = MathAbs(params.entry_price - params.sl_price);
      if(sl_dist < min_dist)
        {
         message = StringFormat("Erro: SL muito próximo (mínimo %d pontos, atual %.0f).",
                                stops_level_pts,
                                MathRound(sl_dist / _Point));
         return false;
        }

      // For pending orders also check entry distance from current price:
      if(IsPendingAction(g_state.action))
        {
         MqlTick tick;
         if(SymbolInfoTick(_Symbol, tick))
           {
            double ref_price  = is_buy ? tick.ask : tick.bid;
            double entry_dist = MathAbs(params.entry_price - ref_price);
            if(entry_dist < min_dist)
              {
               message = StringFormat("Erro: entrada pendente muito próxima do preço atual (mínimo %d pontos).",
                                      stops_level_pts);
               return false;
              }
           }
        }

      // TP distance check (if TP set):
      if(params.tp_points > 0.0 && params.tp_price > 0.0)
        {
         double tp_dist = MathAbs(params.entry_price - params.tp_price);
         if(tp_dist < min_dist)
           {
            message = StringFormat("Erro: TP muito próximo (mínimo %d pontos, atual %.0f).",
                                   stops_level_pts,
                                   MathRound(tp_dist / _Point));
            return false;
           }
        }
     }

   // ── 8. Freeze level (additional broker constraint) ────────────────
   int freeze_level_pts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   if(freeze_level_pts > 0 && IsPendingAction(g_state.action))
     {
      MqlTick tick;
      if(SymbolInfoTick(_Symbol, tick))
        {
         double ref_price  = is_buy ? tick.ask : tick.bid;
         double entry_dist = MathAbs(params.entry_price - ref_price);
         double freeze_dist = freeze_level_pts * _Point;
         if(entry_dist < freeze_dist)
           {
            message = StringFormat("Aviso: entrada dentro da zona de freeze do broker (%d pontos).",
                                   freeze_level_pts);
            // This is a warning but still treat as blocking for safety:
            return false;
           }
        }
     }

   // ── All checks passed ─────────────────────────────────────────────
   string action_lbl = EffectiveActionLabel(g_state.action, params.entry_price);

   // lots_origin: show risk% and money when in percent mode
   string lots_origin = "";
   if(g_state.risk_mode == RISK_MODE_PERCENT && params.risk_pct > 0.0)
      lots_origin = StringFormat(" [%.2f%%=$%.2f]", params.risk_pct, params.risk_money);

   // TP field: price + points, or "sem TP"
   string tp_str = (params.tp_price > 0.0)
                   ? StringFormat(", TP %s (%.0f pt)", FormatPrice(params.tp_price), params.tp_points)
                   : ", sem TP";

   message = StringFormat("Pronto: %s, %s lots%s, entrada %s, SL %s (%.0f pt)%s",
                          action_lbl,
                          FormatLots(params.lots), lots_origin,
                          FormatPrice(params.entry_price),
                          FormatPrice(params.sl_price), params.sl_points,
                          tp_str);
   return true;
  }

//+------------------------------------------------------------------+
//|  ClearTradeDraftAfterSuccessfulSend                               |
//|  Desmonta o esboço da operação sem apagar a mensagem de sucesso.  |
//|  Chamado exclusivamente no ramo de sucesso real do Send.          |
//+------------------------------------------------------------------+

void ClearTradeDraftAfterSuccessfulSend()
  {
   g_state.action      = ACTION_NONE;
   g_state.entry_price = 0.0;
   g_state.active_edit = EDIT_TARGET_NONE;
   // Não tocar no status — a mensagem de sucesso permanece visível
   g_panel.RefreshActionButtons();
   g_panel.RefreshValues();
   DeletePreviewObjects();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//|  SendSelectedOrder — FASE 4C: hardened real trade execution       |
//|                                                                  |
//|  Receives the plan already built and validated by the caller.    |
//|  Does NOT call BuildTradePlan or ValidateTradeRequest again —    |
//|  the caller owns the single build/validate cycle.               |
//|                                                                  |
//|  Safety gates ported from Position Sizer Trading.mqh:            |
//|    1. TERMINAL_CONNECTED                                         |
//|    2. TERMINAL_TRADE_ALLOWED                                     |
//|    3. MQL_TRADE_ALLOWED                                          |
//|    4. ACCOUNT_TRADE_ALLOWED + ACCOUNT_TRADE_EXPERT               |
//|    5. SYMBOL_TRADE_MODE                                          |
//|                                                                  |
//|  Pre-dispatch failures are tagged [PRE-DISPATCH] in logs.        |
//|  Broker retcode failures are tagged [BROKER] in logs.            |
//|                                                                  |
//|  Dispatch rules:                                                 |
//|    ACTION_BUY          -> g_trade.Buy(...)                       |
//|    ACTION_SELL         -> g_trade.Sell(...)                       |
//|    ACTION_BUY_PENDING  -> BuyStop / BuyLimit (by subtype)        |
//|    ACTION_SELL_PENDING -> SellStop / SellLimit (by subtype)      |
//+------------------------------------------------------------------+

bool SendSelectedOrder(const TradeParams &plan)
  {
   PendingSubtype st = DerivePendingSubtype(g_state.action, plan.entry_price);
   string effective_type = EffectiveActionLabel(g_state.action, plan.entry_price);

   // ══════════════════════════════════════════════════════════════════
   //  PART A — Pre-dispatch safety gates (ported from Position Sizer)
   //  If any of these fail, we NEVER call CTrade.  The failure is
   //  categorised as [PRE-DISPATCH] so it is immediately clear that
   //  the request was never sent to the broker.
   // ══════════════════════════════════════════════════════════════════

   // 1. Terminal connected to broker server?
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
     {
      string reason = "Terminal desconectado do servidor.";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }

   // 2. Algo trading enabled globally in terminal? (AutoTrading button)
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      string reason = "Algo trading desabilitado no terminal (botão AutoTrading).";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }

   // 3. This EA allowed to trade? (EA properties / "Allow Algo Trading")
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      string reason = "Algo trading desabilitado para este EA.";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }

   // 4. Account-level trading permission
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
     {
      string reason = "Conta não permite trading (ACCOUNT_TRADE_ALLOWED=false).";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     {
      string reason = "Conta não permite trading por EAs (ACCOUNT_TRADE_EXPERT=false).";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }

   // 5. Symbol trade mode — is trading allowed on this instrument?
   ENUM_SYMBOL_TRADE_MODE sym_mode =
      (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(sym_mode == SYMBOL_TRADE_MODE_DISABLED)
     {
      string reason = "Símbolo " + _Symbol + " está desabilitado para trading.";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }
   if(sym_mode == SYMBOL_TRADE_MODE_CLOSEONLY)
     {
      string reason = "Símbolo " + _Symbol + " só permite fechar posições (close-only).";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }
   // SYMBOL_TRADE_MODE_LONGONLY / SHORTONLY quick-guards
   if(sym_mode == SYMBOL_TRADE_MODE_LONGONLY && !IsBuyAction(g_state.action))
     {
      string reason = _Symbol + " só permite operações Long.";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }
   if(sym_mode == SYMBOL_TRADE_MODE_SHORTONLY && IsBuyAction(g_state.action))
     {
      string reason = _Symbol + " só permite operações Short.";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }

   // ══════════════════════════════════════════════════════════════════
   //  Pre-send diagnostics log (execution mode, filling)
   // ══════════════════════════════════════════════════════════════════

   ENUM_SYMBOL_TRADE_EXECUTION exec_mode =
      (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
   Print("=== LotForge Manager — REAL SEND ===");
   Print("Action      : ", effective_type);
   Print("Symbol      : ", _Symbol,
         "  mode=", EnumToString(sym_mode),
         "  exec=", EnumToString(exec_mode));
   Print("Filling     : ", EnumToString((ENUM_ORDER_TYPE_FILLING)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE)));
   Print("Entry       : ", FormatPrice(plan.entry_price));
   Print("SL          : ", FormatPrice(plan.sl_price),
         "  (", FormatPoints(plan.sl_points), " pt)");
   Print("TP          : ", plan.tp_price > 0.0 ? FormatPrice(plan.tp_price) : "---",
         "  (", FormatPoints(plan.tp_points), " pt)");
   Print("Lots        : ", FormatLots(plan.lots));
   Print("Comment     : ", g_state.order_comment);

   // ══════════════════════════════════════════════════════════════════
   //  DISPATCH — all prechecks passed, send to broker
   // ══════════════════════════════════════════════════════════════════

   bool ok = false;

   switch(g_state.action)
     {
      case ACTION_BUY:
         ok = g_trade.Buy(plan.lots, _Symbol,
                          0.0,                  // market price
                          plan.sl_price,
                          plan.tp_price,
                          g_state.order_comment);
         break;

      case ACTION_SELL:
         ok = g_trade.Sell(plan.lots, _Symbol,
                           0.0,                 // market price
                           plan.sl_price,
                           plan.tp_price,
                           g_state.order_comment);
         break;

      case ACTION_BUY_PENDING:
         if(st == PENDING_STOP)
            ok = g_trade.BuyStop(plan.lots, plan.entry_price, _Symbol,
                                 plan.sl_price, plan.tp_price,
                                 ORDER_TIME_GTC, 0,
                                 g_state.order_comment);
         else
            ok = g_trade.BuyLimit(plan.lots, plan.entry_price, _Symbol,
                                  plan.sl_price, plan.tp_price,
                                  ORDER_TIME_GTC, 0,
                                  g_state.order_comment);
         break;

      case ACTION_SELL_PENDING:
         if(st == PENDING_STOP)
            ok = g_trade.SellStop(plan.lots, plan.entry_price, _Symbol,
                                  plan.sl_price, plan.tp_price,
                                  ORDER_TIME_GTC, 0,
                                  g_state.order_comment);
         else
            ok = g_trade.SellLimit(plan.lots, plan.entry_price, _Symbol,
                                   plan.sl_price, plan.tp_price,
                                   ORDER_TIME_GTC, 0,
                                   g_state.order_comment);
         break;

      default:
         Print("[PRE-DISPATCH] Ação desconhecida: ", g_state.action);
         SetStatus("Erro: ação desconhecida.", true);
         return false;
     }

   // ══════════════════════════════════════════════════════════════════
   //  BROKER FEEDBACK — request was sent; inspect retcode
   // ══════════════════════════════════════════════════════════════════

   uint   retcode      = g_trade.ResultRetcode();
   string retcode_desc = g_trade.ResultRetcodeDescription();
   ulong  result_order = g_trade.ResultOrder();
   ulong  result_deal  = g_trade.ResultDeal();

   Print("Retcode     : ", retcode, " — ", retcode_desc);
   if(result_order > 0) Print("Order ticket: ", result_order);
   if(result_deal  > 0) Print("Deal  ticket: ", result_deal);
   Print("================================");

   if(ok && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED))
     {
      // ── Success ────────────────────────────────────────────────────
      if(IsMarketAction(g_state.action))
        {
         string msg = StringFormat("✓ %s enviado — %s lots @ %s | ticket #%d",
                                   effective_type,
                                   FormatLots(plan.lots),
                                   FormatPrice(plan.entry_price),
                                   (int)result_order);
         if(result_deal > 0)
            msg += StringFormat(" deal #%d", (int)result_deal);
         SetStatus(msg, true);
        }
      else
        {
         SetStatus(StringFormat("✓ %s colocado — %s lots @ %s | ticket #%d",
                                effective_type,
                                FormatLots(plan.lots),
                                FormatPrice(plan.entry_price),
                                (int)result_order), true);
        }
      Print("[BROKER] Trade SUCCESS: ", g_state.status_text);
      // Desmontar esboço — a mensagem de sucesso já foi fixada antes desta chamada
      ClearTradeDraftAfterSuccessfulSend();
      return true;
     }
   else
     {
      // ── Broker rejection ───────────────────────────────────────────
      string fail_msg = StringFormat("✗ %s FALHOU — [%d] %s",
                                     effective_type,
                                     retcode, retcode_desc);
      SetStatus(fail_msg, true);
      Print("[BROKER] Trade FAILED: ", fail_msg);
      return false;
     }
  }

//+------------------------------------------------------------------+
//|  ██  STEPPERS                                                    |
//+------------------------------------------------------------------+

void AdjustLots(const int direction)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   g_state.lots = NormalizeVolumeValue(g_state.lots + step * direction);
   g_panel.RefreshValues();
   ChartRedraw(0);
  }

void AdjustEntry(const int direction)
  {
   if(g_state.entry_price <= 0.0)
      g_state.entry_price = CurrentReferencePrice(IsBuyAction(g_state.action));
   if(g_state.entry_price <= 0.0) return;
   double step = InpEntryStepPoints * _Point;
   g_state.entry_price = NormalizePriceValue(g_state.entry_price + step * direction);
   if(g_state.entry_price < 0.0) g_state.entry_price = 0.0;
   g_panel.RefreshValues();
   ChartRedraw(0);
  }

void AdjustDistance(double &distance_points, const int direction)
  { distance_points = MathMax(0.0, distance_points + InpDistanceStepPoints * direction); }


//+------------------------------------------------------------------+
//|  ██  PREVIEW — ETAPA 3.5                                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|  EnsurePreviewLine — OBJ_HLINE para as três linhas horizontais   |
//+------------------------------------------------------------------+

void EnsurePreviewLine(const string kind,
                       const double price,
                       const color  clr,
                       const int    line_style,
                       const int    line_width,
                       const string tooltip)
  {
   string name = PREV_PFX + kind + "_line";
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_HLINE, 0, TimeCurrent(), price)) return;
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK,       true);
     }
   ObjectSetDouble(0,  name, OBJPROP_PRICE,   price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,   clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,   line_style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,   line_width);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP, tooltip);
  }

//+------------------------------------------------------------------+
//|  PreviewCandleCount / CalcPreviewTimeRange                       |
//+------------------------------------------------------------------+

int PreviewCandleCount()
  {
   int scale = (int)ChartGetInteger(0, CHART_SCALE);
   switch(scale)
     {
      case 5:  return 8;
      case 4:  return 16;
      case 3:  return 32;
      case 2:  return 64;
      case 1:  return 128;
      default: return 256;
     }
  }

void CalcPreviewTimeRange(datetime &t1, datetime &t2)
  {
   int candles = PreviewCandleCount();

   // t2: right edge = open of the last fully-closed bar (shift 1).
   // Fallback chain: shift1 -> shift0 -> TimeCurrent().
   datetime bar_right = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(bar_right == 0) bar_right = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bar_right == 0) bar_right = TimeCurrent();
   t2 = bar_right;

   // t1: left edge = open of the bar exactly 'candles' bars to the left of bar1.
   // bar1 is at shift=1 from bar0, so that bar is at shift = 1+candles.
   // Using real iTime() shifts means coverage tracks actual bars, not wall-clock
   // seconds — weekend/holiday gaps and TF changes never distort the range.
   datetime bar_left = iTime(_Symbol, PERIOD_CURRENT, 1 + candles);
   if(bar_left == 0)
      bar_left = bar_right - (datetime)((long)candles * PeriodSeconds()); // fallback
   t1 = bar_left;
  }

//+------------------------------------------------------------------+
//|  IsMouseOverPanel — delegates to g_panel                         |
//+------------------------------------------------------------------+

bool IsMouseOverPanel(const int mouse_x, const int mouse_y)
  {
   return g_panel.IsMouseOverPanel(mouse_x, mouse_y);
  }

//+------------------------------------------------------------------+
//|  ██  3.5: DrawPreviewZone — renderer principal                   |
//|                                                                  |
//|  Cria / atualiza dois objetos com o mesmo par (t1, t2):          |
//|    <kind>_zone  — OBJ_RECTANGLE preenchido (a zona de cor)       |
//|    <kind>_text  — OBJ_TEXT centralizado dentro da zona           |
//|                                                                  |
//|  Posicionamento do texto — 3.5b:                                 |
//|                                                                  |
//|  O texto fica COLADO À LINHA de referência de cada zona,         |
//|  não no centro da zona. Isso segue o mock:                       |
//|    TP text  → logo abaixo da linha do TP                         |
//|    Entry text → logo abaixo da linha de entry                    |
//|    SL text  → logo abaixo da linha do SL                         |
//|                                                                  |
//|  Parâmetro text_line_price: preço da linha de referência.        |
//|  ANCHOR_LEFT_UPPER: o ponto de ancoragem fica no canto superior  |
//|  esquerdo do glyph → texto cresce para baixo-direita a partir    |
//|  da linha. Isso posiciona o label "dentro da zona, logo abaixo   |
//|  da borda superior".                                             |
//|                                                                  |
//|  Horizontal: t_text = t1 + (t2-t1)/8, alinhado à esquerda da   |
//|  zona com pequena margem (igual ao mock da imagem 1).            |
//+------------------------------------------------------------------+

void DrawPreviewZone(const string   kind,
                     const datetime t1,
                     const datetime t2,
                     const double   price_hi,
                     const double   price_lo,
                     const color    fill_clr,
                     const color    border_clr,
                     const color    text_clr,
                     const string   label_text,
                     const double   text_line_price)   // preço da linha de referência
  {
   // ── Retângulo de fundo ────────────────────────────────────────────
   string rect_n = PREV_PFX + kind + "_zone";
   if(ObjectFind(0, rect_n) < 0)
     {
      if(!ObjectCreate(0, rect_n, OBJ_RECTANGLE, 0,
                       t1, price_hi, t2, price_lo)) return;
      ObjectSetInteger(0, rect_n, OBJPROP_FILL,       true);
      ObjectSetInteger(0, rect_n, OBJPROP_STYLE,      STYLE_SOLID);
      ObjectSetInteger(0, rect_n, OBJPROP_WIDTH,      1);
      ObjectSetInteger(0, rect_n, OBJPROP_BACK,       true);
      ObjectSetInteger(0, rect_n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, rect_n, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, rect_n, OBJPROP_HIDDEN,     false);
     }
   ObjectSetInteger(0, rect_n, OBJPROP_TIME,  0, t1);
   ObjectSetDouble(0,  rect_n, OBJPROP_PRICE, 0, price_hi);
   ObjectSetInteger(0, rect_n, OBJPROP_TIME,  1, t2);
   ObjectSetDouble(0,  rect_n, OBJPROP_PRICE, 1, price_lo);
   // OBJ_RECTANGLE com FILL=true: OBJPROP_COLOR = cor do preenchimento
   ObjectSetInteger(0, rect_n, OBJPROP_COLOR, fill_clr);

   // Chart-space OBJ_TEXT replaced by screen-space overlay labels.
   // UpdateOverlayPreviewLabel() is called from UpdatePreviewZones().
  }

//+------------------------------------------------------------------+
//|  ErasePreviewZone — remove zona + texto de um kind               |
//+------------------------------------------------------------------+

void ErasePreviewZone(const string kind)
  {
   string rect_n = PREV_PFX + kind + "_zone";
   string text_n = PREV_PFX + kind + "_text";
   if(ObjectFind(0, rect_n) >= 0) ObjectDelete(0, rect_n);
   if(ObjectFind(0, text_n) >= 0) ObjectDelete(0, text_n);
   EraseOverlayLabel(kind);   // also remove screen-space overlay pair
  }


//+------------------------------------------------------------------+
//|  EraseOverlayLabel — remove screen-space overlay pair for a kind |
//+------------------------------------------------------------------+

void EraseOverlayLabel(const string kind)
  {
   string bg_n  = PREV_PFX + kind + "_ovbg";
   string txt_n = PREV_PFX + kind + "_ovtxt";
   if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
   if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
  }

//+------------------------------------------------------------------+
//|  UpdateOverlayPreviewLabel — Position-Sizer-style screen overlay  |
//|                                                                   |
//|  Creates / updates a right-edge-anchored OBJ_RECTANGLE_LABEL +   |
//|  OBJ_LABEL pair positioned from price via ChartTimePriceToXY.    |
//|  Both objects live in screen-space (CORNER_LEFT_UPPER +           |
//|  XDISTANCE/YDISTANCE), OBJPROP_BACK=false — floats above chart   |
//|  and can visually overlap the CAppDialog panel.                   |
//|                                                                   |
//|  No clamping: box can be partially clipped at the right edge,     |
//|  giving the PS line-label "eaten by scale" visual effect.         |
//|                                                                   |
//|  above_line=true  → box sits ABOVE the price line (bottom=py)    |
//|  above_line=false → box sits BELOW the price line (top=py)       |
//+------------------------------------------------------------------+

void UpdateOverlayPreviewLabel(const string kind,
                               const string   text,
                               const double   price,
                               const datetime t1,
                               const datetime t2,
                               const bool     above_line,
                               const color    bg_clr,
                               const color    border_clr,
                               const color    txt_clr)
  {
   // ── Convert t1 / t2 to screen X — same progressive geometry as zone ──
   //  Both calls share the same price; only the X column matters here.
   int px1, px2, py1, py2;
   if(!ChartTimePriceToXY(0, 0, t1, price, px1, py1)) return;
   if(!ChartTimePriceToXY(0, 0, t2, price, px2, py2)) return;

   int bar_x = MathMin(px1, px2) - 2;   // 2px nudge left
   int bar_w = MathAbs(px2 - px1) + 2;  // +2px right extension
   if(bar_w < 1) return;   // degenerate — skip

   // ── Convert price to screen Y ─────────────────────────────────────
   int py = py1;   // py1 == py2 (same price); reuse

   // ── Adaptive font size: start at OVL_FONT_PTS, shrink until text fits ──
   //  Available width = bar_w minus left+right OVL_PAD_X insets.
   //  Font is reduced in 1pt steps down to a minimum of 9pt so the
   //  pending handles do not lose their bold visual weight.
   const int FONT_MIN_PTS = 9;
   int font_pts = OVL_FONT_PTS;
   int avail_w  = MathMax(10, bar_w - 2 * OVL_PAD_X);

   uint tw = 0, th = 0;
   TextSetFont(OVL_FONT, -(font_pts * 10));
   TextGetSize(text, tw, th);
   if(tw == 0 || th == 0)
     { tw = (uint)(StringLen(text) * OVL_FALLBACK_CHAR_W); th = (uint)OVL_FALLBACK_H; }

   while((int)tw > avail_w && font_pts > FONT_MIN_PTS)
     {
      font_pts--;
      TextSetFont(OVL_FONT, -(font_pts * 10));
      tw = 0; th = 0;
      TextGetSize(text, tw, th);
      if(tw == 0 || th == 0)
        { tw = (uint)(StringLen(text) * OVL_FALLBACK_CHAR_W); th = (uint)OVL_FALLBACK_H; }
     }

   int box_h = OVL_BAR_H;   // fixed height — same for all three bars

   // ── Vertical placement ────────────────────────────────────────────
   int box_y;
   if(above_line)
      box_y = py - OVL_LINE_OFFSET - box_h;   // bottom of box touches line
   else
      box_y = py + OVL_LINE_OFFSET;            // top of box touches line

   // ── Text: left-inset alignment, optically centred vertically ─────
   int txt_x = bar_x + OVL_PAD_X;
   int txt_y = box_y + MathMax(1, (OVL_BAR_H - (int)th) / 2 - 1);

   // ── OBJ_RECTANGLE_LABEL — spans same extent as the colored zone ───
   string bg_n = PREV_PFX + kind + "_ovbg";
   if(ObjectFind(0, bg_n) < 0)
     {
      if(!ObjectCreate(0, bg_n, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, bg_n, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, bg_n, OBJPROP_HIDDEN,       false);
      ObjectSetInteger(0, bg_n, OBJPROP_BACK,         false);
      ObjectSetInteger(0, bg_n, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg_n, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
     }
   ObjectSetInteger(0, bg_n, OBJPROP_XDISTANCE, bar_x);
   ObjectSetInteger(0, bg_n, OBJPROP_YDISTANCE, box_y);
   ObjectSetInteger(0, bg_n, OBJPROP_XSIZE,     bar_w);
   ObjectSetInteger(0, bg_n, OBJPROP_YSIZE,     box_h);
   ObjectSetInteger(0, bg_n, OBJPROP_BGCOLOR,   bg_clr);
   ObjectSetInteger(0, bg_n, OBJPROP_COLOR,     border_clr);

   // ── OBJ_LABEL — text centered inside the bar ─────────────────────
   string txt_n = PREV_PFX + kind + "_ovtxt";
   if(ObjectFind(0, txt_n) < 0)
     {
      if(!ObjectCreate(0, txt_n, OBJ_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, txt_n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, txt_n, OBJPROP_HIDDEN,     false);
      ObjectSetInteger(0, txt_n, OBJPROP_BACK,       false);
      ObjectSetInteger(0, txt_n, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, txt_n, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
      ObjectSetString(0,  txt_n, OBJPROP_FONT,       OVL_FONT);
      ObjectSetInteger(0, txt_n, OBJPROP_FONTSIZE,   font_pts);   // initial; always updated below
     }
   // Always re-apply font and font size when the same overlay label is reused
   // across action changes (e.g. Buy -> Buy Pending).
   ObjectSetString(0,  txt_n, OBJPROP_FONT,       OVL_FONT);
   ObjectSetInteger(0, txt_n, OBJPROP_FONTSIZE,   font_pts);
   ObjectSetInteger(0, txt_n, OBJPROP_XDISTANCE, txt_x);
   ObjectSetInteger(0, txt_n, OBJPROP_YDISTANCE, txt_y);
   ObjectSetString(0,  txt_n, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, txt_n, OBJPROP_COLOR,     txt_clr);
  }

//+------------------------------------------------------------------+
//|  ██  4A.1: UpdatePreviewZones — labels built from real plan      |
//|                                                                  |
//|  When plan_valid=true, labels use financial data from the plan:  |
//|    Entry: "Buy (Stop) <price> | Lots <lots>"   — side/subtype    |
//|    SL:    "SL <price> | -$<risk> | <risk_pct>%"                 |
//|    TP:    "TP <price> | +$<reward> | <gain_pct>%"               |
//|                                                                  |
//|  RR is never shown on overlay bars.                              |
//|  "Pending" is never shown in the Entry bar text.                 |
//|  When plan_valid=false, falls back to price-only labels —        |
//|  geometry is still drawn; only text is degraded.                 |
//+------------------------------------------------------------------+

void UpdatePreviewZones(const double   entry_price,
                        const double   sl_price,
                        const double   tp_price,
                        const datetime t1,
                        const datetime t2,
                        const TradeParams &plan,
                        const bool     plan_valid)
  {
   double band = ENTRY_BAND_HALF_PTS * _Point;

   bool is_buy = IsBuyAction(g_state.action);

   // ── zone_sep: align TP/SL inner edges with the entry band outer edges.
   //  Both the TP zone bottom and the SL zone top are set to entry ± band,
   //  which is the exact same outer boundary used by the entry band rectangle.
   //  This makes the three zones tile perfectly — no geometric overlap,
   //  no sub-pixel bleed, no visible gap.
   double zone_sep = band;   // = ENTRY_BAND_HALF_PTS * _Point

   // ── TP zone ───────────────────────────────────────────────────────
   if(tp_price > 0.0)
     {
      // Inner edge pulled one tick TOWARD TP so it does not share the
      // exact entry_price boundary with the SL rectangle below.
      double tp_hi, tp_lo;
      if(tp_price > entry_price)
        { tp_hi = tp_price; tp_lo = entry_price + zone_sep; }
      else
        { tp_hi = entry_price - zone_sep; tp_lo = tp_price; }

      string tp_lbl;
      if(plan_valid && plan.reward_money > 0.0)
        {
         // Primary path: price + reward $ + percent gain — no RR
         tp_lbl = StringFormat("TP %s | +$%.2f", FormatPrice(tp_price), plan.reward_money);
         if(plan.reward_pct > 0.0)
            tp_lbl += StringFormat(" | %.2f%%", plan.reward_pct);
        }
      else
        {
         // Fallback: plan not yet valid — show price only (no RR, no points)
         tp_lbl = "TP " + FormatPrice(tp_price);
        }

      DrawPreviewZone("tp", t1, t2, tp_hi, tp_lo,
                      CLR_PREV_TP_FILL, CLR_PREV_TP_BORDER,
                      CLR_PREV_TP_TEXT, tp_lbl, tp_price);
      // ── TP overlay bar: must sit OUTWARD from entry (away from the zone)
      //  BUY:  TP is above entry → outward = further UP  → bar ABOVE TP line → above_line=true
      //  SELL: TP is below entry → outward = further DOWN → bar BELOW TP line → above_line=false
      bool tp_bar_above = is_buy;   // true for BUY (bar above line), false for SELL (bar below line)
      UpdateOverlayPreviewLabel("tp", tp_lbl, tp_price, t1, t2,
                                tp_bar_above,
                                CLR_OVL_HANDLE_BG, C'160,160,160', clrBlack);
     }
   else
     {
      ErasePreviewZone("tp");
      EraseOverlayLabel("tp");
     }

   // ── SL zone ───────────────────────────────────────────────────────
   if(sl_price > 0.0)
     {
      // Inner edge pulled one tick TOWARD SL — symmetric with TP fix above.
      double sl_hi, sl_lo;
      if(sl_price < entry_price)
        { sl_hi = entry_price - zone_sep; sl_lo = sl_price; }
      else
        { sl_hi = sl_price; sl_lo = entry_price + zone_sep; }

      string sl_lbl;
      if(plan_valid && plan.risk_money > 0.0)
        {
         sl_lbl = StringFormat("SL %s | -$%.2f", FormatPrice(sl_price), plan.risk_money);
         if(plan.risk_pct > 0.0)
            sl_lbl += StringFormat(" | %.2f%%", plan.risk_pct);
        }
      else
        {
         // Fallback: price + points
         double sl_pts = MathAbs(sl_price - entry_price) / _Point;
         sl_lbl = "SL " + FormatPrice(sl_price) +
                  "  (" + FormatPoints(sl_pts) + " pts)";
        }

      DrawPreviewZone("sl", t1, t2, sl_hi, sl_lo,
                      CLR_PREV_SL_FILL, CLR_PREV_SL_BORDER,
                      CLR_PREV_SL_TEXT, sl_lbl, sl_price);
      // ── SL overlay bar: must sit OUTWARD from entry (away from the zone)
      //  BUY:  SL is below entry → outward = further DOWN → bar BELOW SL line → above_line=false
      //  SELL: SL is above entry → outward = further UP   → bar ABOVE SL line → above_line=true
      bool sl_bar_above = !is_buy;  // false for BUY (bar below line), true for SELL (bar above line)
      UpdateOverlayPreviewLabel("sl", sl_lbl, sl_price, t1, t2,
                                sl_bar_above,
                                CLR_OVL_HANDLE_BG, C'160,160,160', clrBlack);
     }
   else
     {
      ErasePreviewZone("sl");
      EraseOverlayLabel("sl");
     }

   // ── Entry band ────────────────────────────────────────────────────
   {
    string effective_lbl = ShortPreviewLabel(g_state.action, entry_price);
    // Use plan lots when valid (risk-mode may have computed a different
    // lot count than g_state.lots); fall back to g_state.lots otherwise.
    string lots_str = plan_valid
                      ? FormatLots(plan.lots)
                      : FormatLots(g_state.lots);
    string en_lbl = effective_lbl + " " + FormatPrice(entry_price) +
                    " | Lots " + lots_str;

    DrawPreviewZone("en", t1, t2,
                    entry_price + band, entry_price - band,
                    CLR_PREV_EN_FILL, CLR_PREV_EN_BORDER,
                    CLR_PREV_EN_TEXT, en_lbl, entry_price);
    // ── Entry overlay bar: sits on the TRAILING side relative to direction
    //  BUY:  price moves up → entry bar sits BELOW the entry line → above_line=false
    //  SELL: price moves down → entry bar sits ABOVE the entry line → above_line=true
    bool en_bar_above = !is_buy;   // false for BUY (below entry line), true for SELL (above entry line)
    UpdateOverlayPreviewLabel("en", en_lbl, entry_price, t1, t2,
                              en_bar_above,
                              CLR_OVL_HANDLE_BG, C'160,160,160', clrBlack);
   }
  }

void ForcePreviewLinesFlat() { /* linhas SELECTABLE=false — sem necessidade de reset */ }

//+------------------------------------------------------------------+
//|  ██  3.5: UpdatePreview — fluxo principal                        |
//|                                                                  |
//|  Ordem:                                                           |
//|  1. Guard de ação/preview.                                        |
//|  2. Calcula entry/SL/TP.                                          |
//|  3. CalcPreviewTimeRange → t1/t2 (compartilhados).               |
//|  4. EnsurePreviewLine para as três linhas horizontais.            |
//|  5. UpdatePreviewZones para os três blocos OBJ_RECTANGLE+TEXT.   |
//|                                                                  |
//|  Os labels da 3.4 (OBJ_TEXT com ANCHOR_RIGHT à borda t2) foram   |
//|  removidos. O texto agora está DENTRO das zonas (centrado).       |
//+------------------------------------------------------------------+

void UpdatePreview()
  {
   if(g_state.action == ACTION_NONE || !InpShowPreview)
     {
      DeletePreviewObjects();
      return;
     }



   bool is_buy    = IsBuyAction(g_state.action);
   bool is_market = IsMarketAction(g_state.action);

   double entry_price = is_market ? CurrentReferencePrice(is_buy) : g_state.entry_price;
   if(entry_price <= 0.0)
     {
      DeletePreviewObjects();
      return;
     }

   double pt       = _Point;
   double sl_price = 0.0;
   double tp_price = 0.0;

   if(g_state.sl_points > 0.0)
      sl_price = NormalizePriceValue(is_buy ? entry_price - g_state.sl_points * pt
                                           : entry_price + g_state.sl_points * pt);
   if(g_state.tp_points > 0.0)
      tp_price = NormalizePriceValue(is_buy ? entry_price + g_state.tp_points * pt
                                           : entry_price - g_state.tp_points * pt);

   // ── Attempt real plan for financial labels ────────────────────────
   // Two-stage check: build must succeed AND validation must pass.
   // Geometry is drawn from raw g_state prices regardless (below).
   // Financial labels (risk $, reward $, %, RR) only appear when the
   // plan is fully valid — i.e. would not be rejected at Send time.
   TradeParams plan;
   string      build_reason;
   string      validate_msg;
   bool        plan_built = BuildTradePlan(plan, build_reason);
   bool        plan_valid = plan_built && ValidateTradeRequest(plan, validate_msg);

   // ── Shared time range ─────────────────────────────────────────────
   datetime t1, t2;
   CalcPreviewTimeRange(t1, t2);

   // ── Horizontal lines (drag handles) ──────────────────────────────
   string effective_lbl = EffectiveActionLabel(g_state.action, entry_price);
   EnsurePreviewLine("entry", entry_price,
                     CLR_ENTRY_LINE, STYLE_DASH, 1,
                     effective_lbl + " @ " + FormatPrice(entry_price));
   if(sl_price > 0.0)
      EnsurePreviewLine("sl", sl_price, CLR_SL_LINE, STYLE_DASH, 1,
                        "SL @ " + FormatPrice(sl_price));
   else
     {
      string sl_ln = PREV_PFX + "sl_line";
      if(ObjectFind(0, sl_ln) >= 0) ObjectDelete(0, sl_ln);
      EraseOverlayLabel("sl");
     }
   if(tp_price > 0.0)
      EnsurePreviewLine("tp", tp_price, CLR_TP_LINE, STYLE_DASH, 1,
                        "TP @ " + FormatPrice(tp_price));
   else
     {
      string tp_ln = PREV_PFX + "tp_line";
      if(ObjectFind(0, tp_ln) >= 0) ObjectDelete(0, tp_ln);
      EraseOverlayLabel("tp");
     }

   // ── Zone rectangles + financial text ─────────────────────────────
   UpdatePreviewZones(entry_price, sl_price, tp_price, t1, t2, plan, plan_valid);

   // ── Phase 4B: preview guidance must NOT overwrite sticky status ──
   if(!g_status_sticky)
     {
      if(IsPendingAction(g_state.action))
         SetStatus("Ação: " + effective_lbl + ". Configure e clique Send.");
     }

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//|  ██  3.4: DetectLineHit / ApplyLineDrag — inalterados            |
//+------------------------------------------------------------------+

string DetectLineHit(const int mx, const int my)
  {
   if(IsMouseOverPanel(mx, my)) return "";

   bool   is_buy    = IsBuyAction(g_state.action);
   bool   is_market = IsMarketAction(g_state.action);
   double pt        = _Point;

   double entry_p = is_market ? CurrentReferencePrice(is_buy) : g_state.entry_price;
   double sl_p    = 0.0;
   double tp_p    = 0.0;

   if(entry_p > 0.0)
     {
      if(g_state.sl_points > 0.0)
         sl_p = NormalizePriceValue(is_buy ? entry_p - g_state.sl_points * pt
                                           : entry_p + g_state.sl_points * pt);
      if(g_state.tp_points > 0.0)
         tp_p = NormalizePriceValue(is_buy ? entry_p + g_state.tp_points * pt
                                           : entry_p - g_state.tp_points * pt);
     }

   // ── 1st pass: overlay bar rectangles (large easy targets) ─────
   //  Read XDISTANCE/YDISTANCE/XSIZE/YSIZE directly from each _ovbg
   //  screen-space object and test (mx,my) against the bounding box.
   //  Checked before thin-line proximity so the bar is the primary handle.
   {
    string _n; int _bx,_by,_bw,_bh;
    // entry bar (pending only)
    if(IsPendingAction(g_state.action) && entry_p > 0.0)
      {
       _n = PREV_PFX + "en_ovbg";
       if(ObjectFind(0,_n) >= 0)
         {
          _bx=(int)ObjectGetInteger(0,_n,OBJPROP_XDISTANCE);
          _by=(int)ObjectGetInteger(0,_n,OBJPROP_YDISTANCE);
          _bw=(int)ObjectGetInteger(0,_n,OBJPROP_XSIZE);
          _bh=(int)ObjectGetInteger(0,_n,OBJPROP_YSIZE);
          if(mx>=_bx && mx<=_bx+_bw && my>=_by && my<=_by+_bh) return "entry";
         }
      }
    // sl bar
    if(sl_p > 0.0)
      {
       _n = PREV_PFX + "sl_ovbg";
       if(ObjectFind(0,_n) >= 0)
         {
          _bx=(int)ObjectGetInteger(0,_n,OBJPROP_XDISTANCE);
          _by=(int)ObjectGetInteger(0,_n,OBJPROP_YDISTANCE);
          _bw=(int)ObjectGetInteger(0,_n,OBJPROP_XSIZE);
          _bh=(int)ObjectGetInteger(0,_n,OBJPROP_YSIZE);
          if(mx>=_bx && mx<=_bx+_bw && my>=_by && my<=_by+_bh) return "sl";
         }
      }
    // tp bar
    if(tp_p > 0.0)
      {
       _n = PREV_PFX + "tp_ovbg";
       if(ObjectFind(0,_n) >= 0)
         {
          _bx=(int)ObjectGetInteger(0,_n,OBJPROP_XDISTANCE);
          _by=(int)ObjectGetInteger(0,_n,OBJPROP_YDISTANCE);
          _bw=(int)ObjectGetInteger(0,_n,OBJPROP_XSIZE);
          _bh=(int)ObjectGetInteger(0,_n,OBJPROP_YSIZE);
          if(mx>=_bx && mx<=_bx+_bw && my>=_by && my<=_by+_bh) return "tp";
         }
      }
   }

   // ── 2nd pass: thin line Y proximity (fallback) ────────────────
   datetime t_ref = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t_ref == 0) t_ref = TimeCurrent();
   int dummy_x, ly;

   if(IsPendingAction(g_state.action) && entry_p > 0.0)
     {
      ChartTimePriceToXY(0, 0, t_ref, entry_p, dummy_x, ly);
      if(MathAbs(ly - my) <= LINE_HIT_TOL_PX) return "entry";
     }
   if(sl_p > 0.0)
     {
      ChartTimePriceToXY(0, 0, t_ref, sl_p, dummy_x, ly);
      if(MathAbs(ly - my) <= LINE_HIT_TOL_PX) return "sl";
     }
   if(tp_p > 0.0)
     {
      ChartTimePriceToXY(0, 0, t_ref, tp_p, dummy_x, ly);
      if(MathAbs(ly - my) <= LINE_HIT_TOL_PX) return "tp";
     }
   return "";
  }

void ApplyLineDrag(const int mx, const int my)
  {
   bool is_buy    = IsBuyAction(g_state.action);
   bool is_market = IsMarketAction(g_state.action);
   int      subwin;
   datetime t_dummy;
   double   new_price;
   if(!ChartXYToTimePrice(0, mx, my, subwin, t_dummy, new_price)) return;
   if(new_price <= 0.0) return;

   double tick_sz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   new_price = (tick_sz > 0.0)
               ? NormalizePriceValue(MathRound(new_price / tick_sz) * tick_sz)
               : NormalizePriceValue(new_price);

   if(g_drag_line_kind == "entry" && IsPendingAction(g_state.action))
     { g_state.entry_price = new_price; }
   else if(g_drag_line_kind == "sl")
     {
      double ref_e = is_market ? CurrentReferencePrice(is_buy) : g_state.entry_price;
      if(ref_e > 0.0)
        {
         double min_tick = (tick_sz > 0.0) ? tick_sz : _Point;
         bool ok = is_buy ? (new_price < ref_e) : (new_price > ref_e);
         if(!ok) new_price = NormalizePriceValue(is_buy ? ref_e - min_tick : ref_e + min_tick);
         g_state.sl_points = MathMax(1.0, MathRound(MathAbs(new_price - ref_e) / _Point));
        }
     }
   else if(g_drag_line_kind == "tp")
     {
      double ref_e = is_market ? CurrentReferencePrice(is_buy) : g_state.entry_price;
      if(ref_e > 0.0)
        {
         double min_tick = (tick_sz > 0.0) ? tick_sz : _Point;
         bool ok = is_buy ? (new_price > ref_e) : (new_price < ref_e);
         if(!ok) new_price = NormalizePriceValue(is_buy ? ref_e + min_tick : ref_e - min_tick);
         g_state.tp_points = MathMax(1.0, MathRound(MathAbs(new_price - ref_e) / _Point));
        }
     }
  }

//+------------------------------------------------------------------+
//|  ██  HandleMouseMoveDrag — line drag only (panel drag by CAppDialog)
//+------------------------------------------------------------------+

void HandleMouseMoveDrag(const long   mouse_x_l,
                         const double mouse_y_d,
                         const bool   btn_down)
  {
   int mx = (int)mouse_x_l;
   int my = (int)mouse_y_d;

   if(!btn_down)
     {
      if(g_drag_phase == DRAG_ACTIVE_LINE)
        {
         RestoreChartScroll();
         g_drag_phase     = DRAG_IDLE;
         g_drag_line_kind = "";
         if(g_state.action != ACTION_NONE) UpdatePreview();
        }
      else if(g_drag_phase == DRAG_CANDIDATE)
        {
         g_drag_phase     = DRAG_IDLE;
         g_drag_line_kind = "";
        }
      return;
     }

   if(g_drag_phase == DRAG_IDLE)
     {
      // Only detect preview line hits — panel drag handled by CAppDialog
      string hit = (g_state.action != ACTION_NONE && InpShowPreview)
                   ? DetectLineHit(mx, my) : "";
      if(hit != "")
        {
         g_drag_phase     = DRAG_CANDIDATE;
         g_drag_line_kind = hit;
         g_drag_press_x   = mx;
         g_drag_press_y   = my;
        }
      return;
     }

   if(g_drag_phase == DRAG_CANDIDATE)
     {
      int dx = MathAbs(mx - g_drag_press_x);
      int dy = MathAbs(my - g_drag_press_y);
      if(dx + dy < DRAG_THRESHOLD_PX) return;
      SuppressChartScroll();
      g_drag_phase = DRAG_ACTIVE_LINE;
     }

   if(g_drag_phase == DRAG_ACTIVE_LINE)
     {
      ApplyLineDrag(mx, my);
      g_panel.RefreshValues();
      UpdatePreview();
      return;
     }
  }

//+------------------------------------------------------------------+
//|  ██  TradeParams e PanelState — implementações                   |
//+------------------------------------------------------------------+

void TradeParams::Clear()
  {
   entry_price  = 0.0; sl_price    = 0.0; tp_price    = 0.0;
   sl_points    = 0.0; tp_points   = 0.0; lots        = 0.0;
   risk_pct     = 0.0; risk_money  = 0.0; reward_money= 0.0; reward_pct = 0.0; rr_ratio = 0.0;
  }

bool TradeParams::IsValid() const { return (entry_price > 0.0 && lots > 0.0); }

void PanelState::Init()
  {
   panel_x     = InpPanelX;
   panel_y     = InpPanelY;
   minimized   = false;
   action      = ACTION_NONE;
   active_edit = EDIT_TARGET_NONE;
   lots        = InpDefaultLots;
   entry_price = 0.0;
   sl_points   = MathMax(0.0, MathRound(InpDefaultSlPoints));
   tp_points   = MathMax(0.0, MathRound(InpDefaultTpPoints));
   order_comment      = "";
   risk_mode          = InpRiskMode;
   risk_percent       = InpRiskPercent;
   entry_line_visible = false;
   sl_line_visible    = false;
   tp_line_visible    = false;
   rr_zone_visible    = InpShowRRZone;
   break_even_enabled    = false;
   break_even_points     = 0;
   trailing_stop_enabled = false;
   trailing_stop_points  = 0;
   algo_trading_ui_enabled = false;
   preview_busy       = false;
   syncing            = false;
   edit_in_progress   = false;
   editing_object     = EDIT_TARGET_NONE;
   status_text        = "";
  }

void PanelState::Reset() { Init(); }


//+------------------------------------------------------------------+
//|  ██  GESTÃO DE POSIÇÃO — HELPERS E PIPELINE                      |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|  FindManagedIndex — retorna índice do ticket no array interno     |
//|  Retorna -1 se não encontrado.                                    |
//+------------------------------------------------------------------+

int FindManagedIndex(const ulong ticket)
  {
   int n = ArraySize(g_managed_trades);
   for(int i = 0; i < n; i++)
      if(g_managed_trades[i].ticket == ticket)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
//|  EnsureManagedState — cria entrada de estado se ainda não existe  |
//|  Captura risco original na primeira chamada para o ticket.        |
//+------------------------------------------------------------------+

void EnsureManagedState(const ulong ticket)
  {
   if(FindManagedIndex(ticket) >= 0) return;   // já existe

   if(!PositionSelectByTicket(ticket)) return;

   ManagedTradeState ms;
   ms.ticket             = ticket;
   ms.symbol             = PositionGetString(POSITION_SYMBOL);
   ms.initial_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   ms.initial_sl         = PositionGetDouble(POSITION_SL);
   ms.initial_tp         = PositionGetDouble(POSITION_TP);
   ms.initial_risk_points = (ms.initial_sl > 0.0)
                            ? MathAbs(ms.initial_open_price - ms.initial_sl) / _Point
                            : 0.0;
   ms.be_applied         = false;
   ms.partial_done       = false;
   ms.trailing_armed     = false;
   ms.algo_managed       = false;

   int n = ArraySize(g_managed_trades);
   ArrayResize(g_managed_trades, n + 1);
   g_managed_trades[n] = ms;
  }

//+------------------------------------------------------------------+
//|  SyncManagedTradeState — sincroniza array com posições abertas   |
//|  Cria entradas para novas posições. Limpa entradas encerradas.   |
//+------------------------------------------------------------------+

void SyncManagedTradeState()
  {
   // ── 1. Criar entradas para posições abertas do símbolo + magic ───
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagicNumber && magic != 0) continue;
      EnsureManagedState(t);
      // Se Algo Trading ligado ao abrir posição, marcar como algo_managed
      if(g_algo_trading_enabled)
        {
         int idx = FindManagedIndex(t);
         if(idx >= 0 && !g_managed_trades[idx].algo_managed)
           {
            g_managed_trades[idx].algo_managed   = true;
            g_managed_trades[idx].trailing_armed = true;
           }
        }
     }

   // ── 2. Limpar entradas de posições já encerradas ──────────────────
   int n = ArraySize(g_managed_trades);
   for(int i = n - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(g_managed_trades[i].ticket))
        {
         // Apagar markers visuais antes de remover entrada
         EraseManagedTradeMarkers(g_managed_trades[i].ticket);
         // Remover entrada: shift para baixo
         for(int j = i; j < n - 1; j++)
            g_managed_trades[j] = g_managed_trades[j + 1];
         n--;
         ArrayResize(g_managed_trades, n);
        }
     }
  }

//+------------------------------------------------------------------+
//|  IsPositionProtected — SL está do lado seguro (além da entrada)   |
//|  Verifica se o stop já protege a entrada (BE ou melhor).          |
//+------------------------------------------------------------------+

bool IsPositionProtected(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return false;
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   long   type  = PositionGetInteger(POSITION_TYPE);
   if(sl == 0.0) return false;
   if(type == POSITION_TYPE_BUY)  return (sl >= open);
   if(type == POSITION_TYPE_SELL) return (sl <= open);
   return false;
  }

//+------------------------------------------------------------------+
//|  SyncProtectionState — sincroniza be_applied com o SL real       |
//|  Se a posição já estiver protegida no broker, marca be_applied.  |
//|  Chamado antes de qualquer decisão de BE/trailing para evitar    |
//|  loop de reaplicação quando BE já existe externamente.           |
//+------------------------------------------------------------------+

void SyncProtectionState(const int idx)
  {
   if(idx < 0) return;
   if(g_managed_trades[idx].be_applied) return;   // já sincronizado — sair rápido
   if(IsPositionProtected(g_managed_trades[idx].ticket))
      g_managed_trades[idx].be_applied = true;
  }

//+------------------------------------------------------------------+
//|  PositionProgressToTargetPct — % do caminho percorrido até o TP  |
//+------------------------------------------------------------------+

double PositionProgressToTargetPct(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return 0.0;
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double tp    = PositionGetDouble(POSITION_TP);
   double price = PositionGetDouble(POSITION_PRICE_CURRENT);
   long   type  = PositionGetInteger(POSITION_TYPE);
   if(tp == 0.0) return 0.0;
   double total_dist = MathAbs(tp - open);
   if(total_dist <= 0.0) return 0.0;
   double dist_done = (type == POSITION_TYPE_BUY) ? (price - open) : (open - price);
   double pct = (dist_done / total_dist) * 100.0;
   return MathMax(0.0, pct);
  }

//+------------------------------------------------------------------+
//|  TryManualBreakEven — aplica BE imediatamente na posição         |
//|  Move SL para open + offset de proteção.                         |
//|  Não piora stop já protegido.                                    |
//+------------------------------------------------------------------+

bool TryManualBreakEven(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return false;
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);
   long   type = PositionGetInteger(POSITION_TYPE);

   double offset = InpBEProtectOffsetPts * _Point;
   double new_sl;
   if(type == POSITION_TYPE_BUY)
      new_sl = NormalizeDouble(open + offset, _Digits);
   else
      new_sl = NormalizeDouble(open - offset, _Digits);

   // ── Verificar se já está protegido igual ou melhor ────────────────
   if(type == POSITION_TYPE_BUY  && sl > 0.0 && sl >= new_sl)
     {
      // Sincronizar flag interno e sair sem modificação e sem loop
      EnsureManagedState(ticket);
      int idx = FindManagedIndex(ticket);
      if(idx >= 0) g_managed_trades[idx].be_applied = true;
      SetStatus(StringFormat("Posição #%d já protegida (SL=%.5f ≥ BE=%.5f).", ticket, sl, new_sl), true);
      return true;
     }
   if(type == POSITION_TYPE_SELL && sl > 0.0 && sl <= new_sl)
     {
      EnsureManagedState(ticket);
      int idx = FindManagedIndex(ticket);
      if(idx >= 0) g_managed_trades[idx].be_applied = true;
      SetStatus(StringFormat("Posição #%d já protegida (SL=%.5f ≤ BE=%.5f).", ticket, sl, new_sl), true);
      return true;
     }

   // ── Verificar stop level mínimo do broker ────────────────────────
   int stop_lvl = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   double current_price = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
   double min_dist = stop_lvl * _Point;
   if(MathAbs(current_price - new_sl) < min_dist)
     {
      // Ajustar para respeitar stop level
      if(type == POSITION_TYPE_BUY)
         new_sl = NormalizeDouble(current_price - min_dist - _Point, _Digits);
      else
         new_sl = NormalizeDouble(current_price + min_dist + _Point, _Digits);
     }

   if(g_trade.PositionModify(ticket, new_sl, tp))
     {
      // Verificar se o resultado final realmente protege a entrada
      // (o broker pode ter ajustado o SL para cumprir stop level)
      bool really_protected = IsPositionProtected(ticket);
      EnsureManagedState(ticket);
      int idx = FindManagedIndex(ticket);
      if(idx >= 0) g_managed_trades[idx].be_applied = really_protected;
      SetStatus(StringFormat("BE aplicado — #%d SL movido para %.5f.", ticket, new_sl), true);
      Print("[BE Manual] ticket=", ticket, " new_sl=", new_sl, " protected=", really_protected);
      return true;
     }
   else
     {
      SetStatus(StringFormat("Falha ao aplicar BE #%d — erro %d.", ticket, GetLastError()), true);
      Print("[BE Manual] ERRO ticket=", ticket, " err=", GetLastError());
      return false;
     }
  }

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|  TryAutoBreakEven — aplica BE quando posição atinge % do alvo    |
//|  Gatilho: PositionProgressToTargetPct >= InpBETriggerTargetPct   |
//|  Sem TP definido: auto BE não dispara (não inventa alvo).        |
//|  Sem loop: SyncProtectionState garante saída rápida se já prot.  |
//+------------------------------------------------------------------+

bool TryAutoBreakEven(const ulong ticket)
  {
   int idx = FindManagedIndex(ticket);
   if(idx < 0) return false;

   // Sincronizar proteção real antes de qualquer decisão — previne loop
   SyncProtectionState(idx);

   if(g_managed_trades[idx].be_applied) return false;   // já protegido (real ou flag)

   // Validar input do usuário — faixa segura [1, 100]
   double trigger_pct = MathMax(1.0, MathMin(100.0, InpBETriggerTargetPct));

   // Sem TP: não é possível calcular progresso — não disparar auto BE
   // (usuário pode usar BE manual; não inventar alvo alternativo)
   if(!PositionSelectByTicket(ticket)) return false;
   if(PositionGetDouble(POSITION_TP) == 0.0) return false;

   // Verificar se atingiu o percentual configurado do alvo
   double pct = PositionProgressToTargetPct(ticket);
   if(pct < trigger_pct) return false;   // ainda abaixo do gatilho — sair silenciosamente

   // Atingiu o gatilho — aplicar BE
   return TryManualBreakEven(ticket);
  }

//+------------------------------------------------------------------+
//|  TryPartialClose — fecha parcialmente se progresso >= gatilho    |
//|  Executa no máximo uma vez por posição (partial_done).           |
//+------------------------------------------------------------------+

bool TryPartialClose(const ulong ticket)
  {
   int idx = FindManagedIndex(ticket);
   if(idx < 0) return false;
   if(g_managed_trades[idx].partial_done) return false;

   if(!PositionSelectByTicket(ticket)) return false;
   double tp = PositionGetDouble(POSITION_TP);
   if(tp == 0.0) return false;   // sem TP — não inventar alvo

   double pct = PositionProgressToTargetPct(ticket);
   if(pct < InpAlgoPartialTrigger) return false;

   double lote      = PositionGetDouble(POSITION_VOLUME);
   double lote_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lote_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lote_step <= 0.0) lote_step = 0.01;

   double lote_fechar = MathFloor((lote * InpAlgoPartialClosePct / 100.0) / lote_step) * lote_step;
   if(lote_fechar < lote_min)  lote_fechar = lote_min;
   if(lote_fechar >= lote)     lote_fechar = lote_min;   // nunca fechar tudo pelo parcial

   if(lote_fechar < lote_min || lote_fechar >= lote)
     {
      Print("[Parcial] #", ticket, " lote insuficiente para fechar parcialmente (", lote, " lots).");
      g_managed_trades[idx].partial_done = true;   // marcar para não tentar novamente
      return false;
     }

   if(g_trade.PositionClosePartial(ticket, lote_fechar))
     {
      g_managed_trades[idx].partial_done = true;
      string msg = StringFormat("Parcial #%d: %.2f lotes fechados @ %.0f%% do TP.", ticket, lote_fechar, pct);
      SetStatus(msg, true);
      Print("[Parcial] ", msg);
      return true;
     }
   else
     {
      int err = GetLastError();
      Print("[Parcial] ERRO ao fechar parcialmente #", ticket, " err=", err);
      SetStatus(StringFormat("Erro no fechamento parcial #%d — cód. %d. BE/Trailing mantidos.", ticket, err), true);
      // Marcar como feito para não re-tentar em loop; BE e trailing continuam
      g_managed_trades[idx].partial_done = true;
      return false;
     }
  }

//+------------------------------------------------------------------+
//|  TryTrailingStop — avança trailing se condições forem atendidas  |
//|  Nunca piora o stop. Só atua após BE se InpTrailingRequiresBE.   |
//+------------------------------------------------------------------+

bool TryTrailingStop(const ulong ticket)
  {
   int idx = FindManagedIndex(ticket);
   if(idx < 0) return false;
   if(!g_managed_trades[idx].trailing_armed) return false;

   // Sincronizar proteção real antes do gate — aceita BE manual não registrado
   SyncProtectionState(idx);

   // Gate: trailing só após proteção real (be_applied reflete estado real após sync)
   if(InpTrailingRequiresBE && !g_managed_trades[idx].be_applied)
     return false;

   if(!PositionSelectByTicket(ticket)) return false;
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);
   double price = PositionGetDouble(POSITION_PRICE_CURRENT);
   long   type  = PositionGetInteger(POSITION_TYPE);

   // Calcular distância do trailing: usar input ou risco inicial
   double dist_pts = (double)InpTrailingDistPts;
   if(dist_pts <= 0.0)
      dist_pts = g_managed_trades[idx].initial_risk_points;
   if(dist_pts <= 0.0) return false;

   double dist = dist_pts * _Point;
   double new_sl;
   bool   should_move = false;

   if(type == POSITION_TYPE_BUY)
     {
      new_sl = NormalizeDouble(price - dist, _Digits);
      // Floor: nunca abaixo do SL atual (nunca piora proteção conquistada)
      double floor_sl = (sl > 0.0) ? sl : NormalizeDouble(open + InpBEProtectOffsetPts * _Point, _Digits);
      if(new_sl < floor_sl) new_sl = floor_sl;
      if(new_sl > sl + (2.0 * _Point))
         should_move = true;
     }
   else  // SELL
     {
      new_sl = NormalizeDouble(price + dist, _Digits);
      // Ceil: nunca acima do SL atual (nunca piora proteção conquistada)
      double ceil_sl = (sl > 0.0) ? sl : NormalizeDouble(open - InpBEProtectOffsetPts * _Point, _Digits);
      if(new_sl > ceil_sl) new_sl = ceil_sl;
      if(sl == 0.0 || new_sl < sl - (2.0 * _Point))
         should_move = true;
     }

   if(!should_move) return false;

   // Verificar stop level
   int stop_lvl = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   double cur_p = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
   if(MathAbs(cur_p - new_sl) < stop_lvl * _Point) return false;

   if(g_trade.PositionModify(ticket, new_sl, tp))
     {
      Print("[Trailing] #", ticket, " SL -> ", new_sl);
      return true;
     }
   else
     {
      Print("[Trailing] ERRO #", ticket, " err=", GetLastError());
      return false;
     }
  }

//+------------------------------------------------------------------+
//|  RunAutomatedTradeManagement — pipeline completo no OnTick        |
//|  Ordem correta:                                                   |
//|    1. Sincronizar proteção real do ticket (SyncProtectionState)   |
//|    2. Auto BE (só age se não protegido ainda)                     |
//|    3. Trailing (só age se protegido)                              |
//|    4. Parcial (só no pipeline Algo, uma vez por ticket)           |
//+------------------------------------------------------------------+

void RunAutomatedTradeManagement()
  {
   bool auto_be_on    = g_state.break_even_enabled;
   bool auto_trail_on = g_state.trailing_stop_enabled;

   int n = ArraySize(g_managed_trades);
   for(int i = 0; i < n; i++)
     {
      ulong t = g_managed_trades[i].ticket;
      if(!PositionSelectByTicket(t)) continue;   // já fechada — SyncManagedTradeState vai limpar

      bool is_algo = g_managed_trades[i].algo_managed;

      // ── 1. Sincronizar proteção real — base para todas as decisões ─
      SyncProtectionState(i);

      // ── 2. Auto BE ────────────────────────────────────────────────
      if(auto_be_on || is_algo)
         TryAutoBreakEven(t);

      // ── 3. Trailing (aproveita be_applied já sincronizado) ────────
      if(auto_trail_on || is_algo)
         TryTrailingStop(t);

      // ── 4. Parcial (apenas Algo; nunca bloqueia BE/trailing) ──────
      if(is_algo)
         TryPartialClose(t);
     }
  }

//+------------------------------------------------------------------+
//|  ██  MANAGED TRADE MARKERS — Open position visual layer           |
//|                                                                   |
//|  Independent of preview/montage layer. Reads real position data   |
//|  from PositionSelectByTicket(). Own candle-based horizontal       |
//|  geometry: left = bar0-1, right = bar0+PreviewCandleCount() ahead.|
//|  OBJ_RECTANGLE_LABEL + OBJ_LABEL with natural right-edge clip.   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|  UpdateOpenTradeMarker — create/update a single floating handle   |
//|                                                                   |
//|  Candle-based horizontal geometry — independent of preview.       |
//|  · Left anchor  = 1 candle behind bar-0 (shift 1)                 |
//|  · Right span  = PreviewCandleCount() candles (scale-aware: 8–256) |
//|  · Both converted to screen X via ChartTimePriceToXY              |
//|  · Y from price via ChartTimePriceToXY                            |
//|  · OBJ_RECTANGLE_LABEL + OBJ_LABEL in CORNER_LEFT_UPPER          |
//|  · No right-edge clamping — natural "eaten by scale" clipping     |
//+------------------------------------------------------------------+

void UpdateOpenTradeMarker(const string obj_id,
                           const string text,
                           const double price,
                           const bool   above_line,
                           const color  bg_clr,
                           const color  border_clr,
                           const color  txt_clr)
  {
   string bg_n  = MNGD_PFX + obj_id + "_bg";
   string txt_n = MNGD_PFX + obj_id + "_tx";

   // ── Compute candle pixel width from two real bars ─────────────────
   datetime t_bar0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   datetime t_bar1 = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(t_bar0 == 0 || t_bar1 == 0)
     {
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
      return;
     }

   int px0, py0, px1, py1_scr;
   if(!ChartTimePriceToXY(0, 0, t_bar0, price, px0, py0) ||
      !ChartTimePriceToXY(0, 0, t_bar1, price, px1, py1_scr))
     {
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
      return;
     }

   int candle_px = MathAbs(px0 - px1);   // pixel width of 1 candle
   if(candle_px < 1) candle_px = 8;      // fallback

   // Scale-aware span: same candle count as preview handles.
   // PreviewCandleCount() returns 8..256 depending on CHART_SCALE.
   // +1 accounts for the 1-candle-back left anchor (bar-1).
   // Starts 1 candle behind bar-0, extends PreviewCandleCount() candles forward
   int span_candles = PreviewCandleCount() + 1;   // +1 for the 1-back anchor
   int bar_x = px1 - 2;                           // start from bar-1 position
   int bar_w = candle_px * span_candles + 2;      // full scale-aware width
   if(bar_w < 1)
     {
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
      return;
     }

   int py = py0;

   // ── Vertical sanity: hide if off-screen ───────────────────────────
   int chart_h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(py < -OVL_BAR_H || py > chart_h + OVL_BAR_H)
     {
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
      return;
     }

   // ── Adaptive font size: shrink until text fits ────────────────────
   const int FONT_MIN_PTS = 9;
   int font_pts = OVL_FONT_PTS;
   int avail_w  = MathMax(10, bar_w - 2 * OVL_PAD_X);

   uint tw = 0, th = 0;
   TextSetFont(OVL_FONT, -(font_pts * 10));
   TextGetSize(text, tw, th);
   if(tw == 0 || th == 0)
     { tw = (uint)(StringLen(text) * OVL_FALLBACK_CHAR_W); th = (uint)OVL_FALLBACK_H; }

   while((int)tw > avail_w && font_pts > FONT_MIN_PTS)
     {
      font_pts--;
      TextSetFont(OVL_FONT, -(font_pts * 10));
      tw = 0; th = 0;
      TextGetSize(text, tw, th);
      if(tw == 0 || th == 0)
        { tw = (uint)(StringLen(text) * OVL_FALLBACK_CHAR_W); th = (uint)OVL_FALLBACK_H; }
     }

   int box_h = OVL_BAR_H;

   // ── Vertical placement (same model as preview handles) ────────────
   int box_y;
   if(above_line)
      box_y = py - OVL_LINE_OFFSET - box_h;
   else
      box_y = py + OVL_LINE_OFFSET;

   // ── Text position ─────────────────────────────────────────────────
   int txt_x_pos = bar_x + OVL_PAD_X;
   int txt_y_pos = box_y + MathMax(1, (OVL_BAR_H - (int)th) / 2 - 1);

   // ── OBJ_RECTANGLE_LABEL (background bar) ─────────────────────────
   if(ObjectFind(0, bg_n) < 0)
     {
      if(!ObjectCreate(0, bg_n, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, bg_n, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, bg_n, OBJPROP_HIDDEN,       false);
      ObjectSetInteger(0, bg_n, OBJPROP_BACK,         false);
      ObjectSetInteger(0, bg_n, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg_n, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
     }
   ObjectSetInteger(0, bg_n, OBJPROP_XDISTANCE, bar_x);
   ObjectSetInteger(0, bg_n, OBJPROP_YDISTANCE, box_y);
   ObjectSetInteger(0, bg_n, OBJPROP_XSIZE,     bar_w);
   ObjectSetInteger(0, bg_n, OBJPROP_YSIZE,     box_h);
   ObjectSetInteger(0, bg_n, OBJPROP_BGCOLOR,   bg_clr);
   ObjectSetInteger(0, bg_n, OBJPROP_COLOR,     border_clr);

   // ── OBJ_LABEL (text inside the bar) ──────────────────────────────
   if(ObjectFind(0, txt_n) < 0)
     {
      if(!ObjectCreate(0, txt_n, OBJ_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, txt_n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, txt_n, OBJPROP_HIDDEN,     false);
      ObjectSetInteger(0, txt_n, OBJPROP_BACK,       false);
      ObjectSetInteger(0, txt_n, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, txt_n, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
     }
   ObjectSetString(0,  txt_n, OBJPROP_FONT,     OVL_FONT);
   ObjectSetInteger(0, txt_n, OBJPROP_FONTSIZE,  font_pts);
   ObjectSetInteger(0, txt_n, OBJPROP_XDISTANCE, txt_x_pos);
   ObjectSetInteger(0, txt_n, OBJPROP_YDISTANCE, txt_y_pos);
   ObjectSetString(0,  txt_n, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, txt_n, OBJPROP_COLOR,     txt_clr);
  }

//+------------------------------------------------------------------+
//|  EraseManagedTradeMarkers — remove all marker objects for ticket  |
//+------------------------------------------------------------------+

void EraseManagedTradeMarkers(const ulong ticket)
  {
   string pfx = MNGD_PFX + IntegerToString(ticket) + "_";
   string kinds[] = {"tp_bg", "tp_tx", "sl_bg", "sl_tx", "mid_bg", "mid_tx", "be_bg", "be_tx"};
   int cnt = ArraySize(kinds);
   for(int i = 0; i < cnt; i++)
     {
      string n = pfx + kinds[i];
      // Also try the simplified naming
      if(ObjectFind(0, n) >= 0) ObjectDelete(0, n);
     }
   // Fallback: delete by constructed prefix scan
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, pfx) == 0)
         ObjectDelete(0, n);
     }
  }

//+------------------------------------------------------------------+
//|  EraseAllManagedTradeMarkers — remove ALL managed marker objects  |
//+------------------------------------------------------------------+

void EraseAllManagedTradeMarkers()
  {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, MNGD_PFX) == 0)
         ObjectDelete(0, n);
     }
  }

//+------------------------------------------------------------------+
//|  UpdateManagedTradeMarkers — draw TP/SL/Mid markers for ticket   |
//|  Reads real position data only — no dependency on g_state/preview|
//+------------------------------------------------------------------+

void UpdateManagedTradeMarkers(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return;

   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl         = PositionGetDouble(POSITION_SL);
   double tp         = PositionGetDouble(POSITION_TP);
   double volume     = PositionGetDouble(POSITION_VOLUME);
   long   pos_type   = PositionGetInteger(POSITION_TYPE);
   bool   is_buy     = (pos_type == POSITION_TYPE_BUY);

   string tk_str = IntegerToString(ticket);

   // ── Symbol economics for $ calculation ────────────────────────────
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);

   // ── TP marker ─────────────────────────────────────────────────────
   if(tp > 0.0)
     {
      double tp_dist  = MathAbs(tp - open_price);
      double tp_money = 0.0;
      double tp_pct   = 0.0;
      if(tick_size > 0.0 && tick_value > 0.0)
        {
         tp_money = NormalizeDouble(tp_dist / tick_size * tick_value * volume, 2);
         if(balance > 0.0)
            tp_pct = NormalizeDouble(tp_money / balance * 100.0, 2);
        }
      string tp_text = StringFormat("TP %s | +$%.2f", FormatPrice(tp), tp_money);
      if(tp_pct > 0.0)
         tp_text += StringFormat(" | %.2f%%", tp_pct);

      bool tp_above = is_buy;
      UpdateOpenTradeMarker(tk_str + "_tp", tp_text, tp, tp_above,
                            CLR_OVL_HANDLE_BG, CLR_PREV_TP_BORDER, CLR_PREV_TP_TEXT);
     }
   else
     {
      string bg_n  = MNGD_PFX + tk_str + "_tp_bg";
      string txt_n = MNGD_PFX + tk_str + "_tp_tx";
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
     }

   // ── SL marker ─────────────────────────────────────────────────────
   if(sl > 0.0)
     {
      double sl_dist  = MathAbs(sl - open_price);
      double sl_money = 0.0;
      double sl_pct   = 0.0;
      if(tick_size > 0.0 && tick_value > 0.0)
        {
         sl_money = NormalizeDouble(sl_dist / tick_size * tick_value * volume, 2);
         if(balance > 0.0)
            sl_pct = NormalizeDouble(sl_money / balance * 100.0, 2);
        }
      string sl_text = StringFormat("SL %s | -$%.2f", FormatPrice(sl), sl_money);
      if(sl_pct > 0.0)
         sl_text += StringFormat(" | %.2f%%", sl_pct);

      bool sl_above = !is_buy;
      UpdateOpenTradeMarker(tk_str + "_sl", sl_text, sl, sl_above,
                            CLR_OVL_HANDLE_BG, CLR_PREV_SL_BORDER, CLR_PREV_SL_TEXT);
     }
   else
     {
      string bg_n  = MNGD_PFX + tk_str + "_sl_bg";
      string txt_n = MNGD_PFX + tk_str + "_sl_tx";
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
     }

   // ── Mid-target / Partial marker ───────────────────────────────────
   int mgd_idx = FindManagedIndex(ticket);
   bool partial_already_done = (mgd_idx >= 0 && g_managed_trades[mgd_idx].partial_done);

   if(InpShowMidTargetBlock && tp > 0.0 && !partial_already_done)
     {
      double partial_pct = MathMax(1.0, MathMin(100.0, InpAlgoPartialTrigger));
      double mid_price;
      if(is_buy)
         mid_price = NormalizePriceValue(open_price + (tp - open_price) * partial_pct / 100.0);
      else
         mid_price = NormalizePriceValue(open_price - (open_price - tp) * partial_pct / 100.0);

      double mid_dist  = MathAbs(mid_price - open_price);
      double mid_money = 0.0;
      if(tick_size > 0.0 && tick_value > 0.0)
         mid_money = NormalizeDouble(mid_dist / tick_size * tick_value * volume, 2);

      string mid_text = StringFormat("%.0f%% TP | %s | +$%.2f",
                                      partial_pct, FormatPrice(mid_price), mid_money);

      bool mid_above = is_buy;
      UpdateOpenTradeMarker(tk_str + "_mid", mid_text, mid_price, mid_above,
                            CLR_OVL_HANDLE_BG, C'120,140,180', C'40,60,120');
     }
   else
     {
      string bg_n  = MNGD_PFX + tk_str + "_mid_bg";
      string txt_n = MNGD_PFX + tk_str + "_mid_tx";
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
     }

   // ── BE marker ─────────────────────────────────────────────────────
   //  Shows only when position is truly protected (SL on profitable side).
   //  Reflects actual SL level — not necessarily open_price.
   bool show_be = false;
   double be_price = 0.0;
   if(mgd_idx >= 0 && g_managed_trades[mgd_idx].be_applied && sl > 0.0)
     {
      // Verify SL is actually on the profitable side
      if(is_buy && sl >= open_price)
        { show_be = true; be_price = sl; }
      else if(!is_buy && sl <= open_price)
        { show_be = true; be_price = sl; }
     }

   if(show_be)
     {
      double be_dist  = MathAbs(be_price - open_price);
      double be_money = 0.0;
      double be_pct   = 0.0;
      if(tick_size > 0.0 && tick_value > 0.0)
        {
         be_money = NormalizeDouble(be_dist / tick_size * tick_value * volume, 2);
         if(balance > 0.0)
            be_pct = NormalizeDouble(be_money / balance * 100.0, 2);
        }
      string be_text;
      if(be_money > 0.001)
         be_text = StringFormat("BE %s | +$%.2f", FormatPrice(be_price), be_money);
      else
         be_text = StringFormat("BE %s", FormatPrice(be_price));
      if(be_pct > 0.001)
         be_text += StringFormat(" | +%.2f%%", be_pct);

      // BE sits on the entry side: BUY → above_line=false (below entry), SELL → above_line=true
      bool be_above = !is_buy;
      UpdateOpenTradeMarker(tk_str + "_be", be_text, be_price, be_above,
                            CLR_OVL_HANDLE_BG, CLR_BE_BORDER, C'140,90,0');
     }
   else
     {
      string bg_n2  = MNGD_PFX + tk_str + "_be_bg";
      string txt_n2 = MNGD_PFX + tk_str + "_be_tx";
      if(ObjectFind(0, bg_n2)  >= 0) ObjectDelete(0, bg_n2);
      if(ObjectFind(0, txt_n2) >= 0) ObjectDelete(0, txt_n2);
     }
  }

//+------------------------------------------------------------------+
//|  RefreshAllManagedTradeMarkers — called from OnTick after sync   |
//+------------------------------------------------------------------+

void RefreshAllManagedTradeMarkers()
  {
   // ── Build set of active tickets ───────────────────────────────────
   int n = ArraySize(g_managed_trades);
   for(int i = 0; i < n; i++)
     {
      ulong t = g_managed_trades[i].ticket;
      if(PositionSelectByTicket(t))
         UpdateManagedTradeMarkers(t);
      else
         EraseManagedTradeMarkers(t);
     }

   // ── Clean orphan marker objects (tickets no longer in array) ──────
   //  Only run occasionally to avoid overhead — simple scan
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string obj_n = ObjectName(0, i, 0, -1);
      if(StringFind(obj_n, MNGD_PFX) != 0) continue;
      // Extract ticket from name: MNGD_PFX + "ticket_kind_suffix"
      string remainder = StringSubstr(obj_n, StringLen(MNGD_PFX));
      int sep = StringFind(remainder, "_");
      if(sep <= 0) { ObjectDelete(0, obj_n); continue; }
      string tk_part = StringSubstr(remainder, 0, sep);
      ulong tk = (ulong)StringToInteger(tk_part);
      if(tk == 0 || FindManagedIndex(tk) < 0)
         ObjectDelete(0, obj_n);
     }
  }

//+------------------------------------------------------------------+
//|  SaveStateForChartChange / RestoreStateFromChartChange           |
//|                                                                  |
//|  Persist the live panel state into terminal global variables so  |
//|  a timeframe switch (REASON_CHARTCHANGE) reloads the same setup  |
//|  instead of falling back to input defaults.                      |
//|                                                                  |
//|  The snapshot is consumed on restore and deleted, so it never    |
//|  survives a true EA restart or re-attach.                        |
//+------------------------------------------------------------------+

void SaveStateForChartChange()
  {
   GlobalVariableSet(GV_PFX + "valid",  1.0);
   GlobalVariableSet(GV_PFX + "action", (double)g_state.action);
   GlobalVariableSet(GV_PFX + "lots",   g_state.lots);
   GlobalVariableSet(GV_PFX + "rmode",  (double)g_state.risk_mode);
   GlobalVariableSet(GV_PFX + "rpct",   g_state.risk_percent);
   GlobalVariableSet(GV_PFX + "entry",  g_state.entry_price);
   GlobalVariableSet(GV_PFX + "sl",     g_state.sl_points);
   GlobalVariableSet(GV_PFX + "tp",     g_state.tp_points);
   GlobalVariableSet(GV_PFX + "px",     (double)g_state.panel_x);
   GlobalVariableSet(GV_PFX + "py",     (double)g_state.panel_y);
   GlobalVariableSet(GV_PFX + "mini",   g_state.minimized ? 1.0 : 0.0);
  }

bool RestoreStateFromChartChange()
  {
   if(!GlobalVariableCheck(GV_PFX + "valid")) return false;
   if(GlobalVariableGet(GV_PFX + "valid") != 1.0)  return false;

   g_state.action       = (TradePanelAction)(int)GlobalVariableGet(GV_PFX + "action");
   g_state.lots         = GlobalVariableGet(GV_PFX + "lots");
   g_state.risk_mode    = (RiskMode)(int)GlobalVariableGet(GV_PFX + "rmode");
   g_state.risk_percent = GlobalVariableGet(GV_PFX + "rpct");
   g_state.entry_price  = GlobalVariableGet(GV_PFX + "entry");
   g_state.sl_points    = GlobalVariableGet(GV_PFX + "sl");
   g_state.tp_points    = GlobalVariableGet(GV_PFX + "tp");
   g_state.panel_x      = (int)GlobalVariableGet(GV_PFX + "px");
   g_state.panel_y      = (int)GlobalVariableGet(GV_PFX + "py");
   g_state.minimized    = GlobalVariableGet(GV_PFX + "mini") > 0.5;

   // Consume snapshot — do not persist beyond this init cycle
   GlobalVariableDel(GV_PFX + "valid");
   return true;
  }

//+------------------------------------------------------------------+
//|  CalcSmartInitDistance — symbol-aware initial SL/TP in points    |
//|                                                                  |
//|  Priority: ATR(14) > broker stop level floor > input default.    |
//|  Gives enough room to drag on first use without being huge.      |
//+------------------------------------------------------------------+

double CalcSmartInitDistance()
  {
   // ── 1. ATR(14) on previous closed bar ────────────────────────────
   int atr_h = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(atr_h != INVALID_HANDLE)
     {
      double buf[1];
      if(CopyBuffer(atr_h, 0, 1, 1, buf) == 1 && buf[0] > 0.0)
        {
         IndicatorRelease(atr_h);
         double pts = MathRound(buf[0] / _Point);
         return MathMax(50.0, MathMin(10000.0, pts));   // clamp [50, 10000]
        }
      IndicatorRelease(atr_h);
     }

   // ── 2. Broker stop-level floor  ──────────────────────────────────
   int stop_lvl = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stop_lvl > 0)
     {
      double floor_pts = (double)(stop_lvl * 3 + 10);
      return MathMax(floor_pts, InpDefaultSlPoints);
     }

   // ── 3. Input default (last resort) ───────────────────────────────
   return MathMax(50.0, InpDefaultSlPoints);
  }

//+------------------------------------------------------------------+
//|  ██  OnInit                                                      |
//+------------------------------------------------------------------+

int OnInit()
  {
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   g_state.Init();
   if(!RestoreStateFromChartChange())
     {
      // Fresh session: use input defaults + smart initial distances
      g_state.lots    = NormalizeVolumeValue(InpDefaultLots);
      g_state.panel_x = InpPanelX;
      g_state.panel_y = InpPanelY;
      double init_dist    = CalcSmartInitDistance();
      g_state.sl_points   = init_dist;
      g_state.tp_points   = MathRound(init_dist * 1.5);   // 1:1.5 RR default
     }
   // If restored: g_state already has sl/tp/lots/position from before TF change

   DeleteByPrefix();
   g_trade_plan.Clear();

   // Use restored coordinates when available (REASON_CHARTCHANGE path).
   // g_state.panel_x/y already hold either the restored position or the
   // InpPanelX/Y defaults — the conditional above took care of that.
   if(!g_panel.CreatePanel(0, PANEL_TITLE, 0, g_state.panel_x, g_state.panel_y))
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
   ChartRedraw(0);
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
   DeletePreviewObjects();
   EraseAllManagedTradeMarkers();
   g_panel.Destroy(reason);
   if(reason == REASON_CHARTCHANGE)
      SaveStateForChartChange();   // preserve setup across TF switch
   else
      DeleteByPrefix();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//|  ██  OnTick / OnTimer                                            |
//+------------------------------------------------------------------+

void OnTick()
  {
   // ── 1. Preview update ────────────────────────────────────────────
   if(g_state.action != ACTION_NONE) UpdatePreview();

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
   RefreshAllManagedTradeMarkers();
  }

void OnTimer()
  { if(g_state.action != ACTION_NONE) UpdatePreview(); }

//+------------------------------------------------------------------+
//|  ██  OnChartEvent                                                |
//+------------------------------------------------------------------+

void OnChartEvent(const int id,
                  const long   &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   // ── CAppDialog event routing (handles panel drag/minimize/etc.) ──
   g_panel.ChartEvent(id, lparam, dparam, sparam);

   if(id == CHARTEVENT_CHART_CHANGE)
     {
      UpdatePreview();
      RefreshAllManagedTradeMarkers();
      return;
     }

   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      bool btn_down = ((StringToInteger(sparam) & 1) != 0);
      HandleMouseMoveDrag(lparam, dparam, btn_down);
      return;
     }
  }
//+------------------------------------------------------------------+
