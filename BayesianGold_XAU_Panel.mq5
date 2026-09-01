//+------------------------------------------------------------------+
//|                                      BayesianGold_XAU_Panel.mq5   |
//|   MT5 v1.78 — motor bayesiano (RSI+CCI) + PANEL tipo dashboard.   |
//|   4 perfiles, BE por % al TP, trailing por % de ganancia,        |
//|   pestanas CTA/CFG/STAT/INTEL + DIAGNOSTICAR.                     |
//|   OnTester() + GUIA DE CALIBRACION incrustada. Codigo abierto.    |
//|   NO promete rentabilidad. Uso bajo tu propio riesgo.            |
//+------------------------------------------------------------------+
#property copyright "Plantilla abierta"
#property version   "1.78"
#property strict
#define BG_VERSION "v1.78"
#property description "BAYESIAN STRATEGY PRO"
#property description "Robot bayesiano para XAUUSD (Oro) en M5."
#property description "Motor RSI+CCI, Shield, Break-even, Trailing, 4 perfiles."
#property description "Codigo abierto. NO promete rentabilidad. Uso bajo tu propio riesgo."

#include <Trade/Trade.mqh>

/*====================================================================
  GUIA DE CALIBRACION (resumen) — criterio en OnTester() abajo.
  - Modelado "Every tick based on real ticks"; XAUUSD de TU broker;
    spread realista (25-40 pts); 4-6 anios de historial.
  - IN-SAMPLE ~70% optimizar / OUT-OF-SAMPLE ~30% solo validar.
    Aceptar si PF_OOS>=0.6*PF_IS y DD_OOS<=1.5*DD_IS.
  - Pasadas (genetico): P1 motor (Threshold,W_RSI,W_CCI,W_Slope,
    W_Return,W_Trend); P2 salidas (SL_ATR,TP_R,BE_Pct,Trail_Pct);
    P3 filtros (ATRMin/Max, RSI_Long/Short).
  - Elegir MESETA, no el pico. Capas OFF al calibrar. Si no hay
    meseta rentable en OOS, el edge no esta ahi: cambiar hipotesis.
====================================================================*/

//====================================================================
//  INPUTS  (nombres y valores del .set de produccion)
//====================================================================
input group "==  ACTIVACION  =="
input string Codigo_Activacion   = "Strader2026";   // Codigo de acceso (cuentas +15k). Pidelo en t.me/straderShop

input group "==  CONFIGURACION DEL ROBOT  =="
input double StartingLots         = 0.03;   // Con que lote quieres empezar? (ej. 0.01)
input double TakeProfit           = 0.0;     // Cuanta ganancia buscas por ciclo? (puntos, 0 = TP largo por ATR)
input double Max_SL_Puntos        = 1000.0;  // No abrir si el SL supera estos puntos (0 = sin limite)
enum ELayerMult
{
   LM_10=10, // x1.0 Sin martingala (recomendado oro)
   LM_11=11, // x1.1
   LM_12=12, // x1.2
   LM_13=13, // x1.3 (Default forex)
   LM_14=14, // x1.4
   LM_15=15, // x1.5
   LM_16=16, // x1.6
   LM_17=17, // x1.7
   LM_18=18, // x1.8
   LM_19=19, // x1.9
   LM_20=20  // x2.0 Agresivo
};
input ELayerMult Layer_Multiplier = LM_10;   // Que multiplicador de lote? (deja x1.0 si dudas)
input int    MaxTrades            = 999;   // Cuantas operaciones puede abrir como maximo?
input bool   AutoCompound         = false;   // Quieres que el lote crezca con tu balance?
input int    Identifier           = 0;   // Que ID le das? (cambialo si corres varios bots)

input group "==  PROTECCIONES  =="
input bool   Usar_Shield          = true;   // Quieres activar el Shield? (cierra todo si pierde X%)
input bool   Usar_FrenoRachas     = true;   // Parar tras X cierres sin ganar (SL o break-even)?
input int    Perdidas_Seguidas    = 2;      // Cuantos SL/break-even seguidos para parar?
input double Shield_Pct           = 15.0;  // Cual es tu perdida maxima por dia? (% ej. 5)
input bool   Usar_Objetivo        = true;   // Quieres que cierre todo al llegar a una meta?
input double Objetivo_Diario      = 20.0;    // Cual es tu meta de ganancia del dia? (% del balance)
input double Meta_Mensual         = 0.0;   // Cual es tu meta mensual? (USD, 0=sin meta)
input bool   Usar_Breakeven       = true;   // Quieres activar el Break Even? (mueve SL a entrada)
input double BE_Activacion        = 80.0;   // A que % del TP se activa el Break Even? (ej. 80)
input bool   Usar_Trailing        = false;   // Quieres activar el Trailing Stop? (asegura ganancia)
input double Trailing_Activar     = 30.0;   // A que % del TP empieza el Trailing? (ej. 30)
input double Trailing_Dist        = 75.0;   // Que % del avance asegura el Trailing? (ej. 75)

input group "==  HORARIOS Y SESIONES  =="
input bool   Usar_Hora_Local      = true;   // Quieres usar la hora de tu computadora?
input bool   Operar_24H           = false;   // Quieres que el robot opere las 24 horas?
input bool   Sesion_NuevaYork     = true;   // Quieres que opere solo en sesion Nueva York?
input int    NY_Hora_Inicio       = 8;   // A que hora quieres que inicie Nueva York?
input int    NY_Hora_Cierre       = 11;   // A que hora quieres que cierre Nueva York?
input bool   Sesion_Asia          = true;   // Quieres que opere solo en sesion Asia?
input int    Asia_Hora_Inicio     = 22;   // A que hora quieres que inicie Asia?
input int    Asia_Hora_Cierre     = 2;   // A que hora quieres que cierre Asia?
input bool   Sesion_Londres       = true;   // Quieres que opere solo en sesion Londres?
input int    Londres_Hora_Inicio  = 2;   // A que hora quieres que inicie Londres?
input int    Londres_Hora_Cierre  = 11;   // A que hora quieres que cierre Londres?

input group "==  FILTROS DE ENTRADA  =="
input bool   Usar_Spread_Max      = true;   // Quieres evitar operar si el spread esta alto?
input double Spread_Max           = 30.0;   // Cual es el spread maximo que permites? (puntos)
input bool   Usar_Margen          = true;   // Quieres revisar el margen antes de cada operacion?
input double Margen_Minimo        = 20.0;   // Cual es el margen libre minimo? (% ej. 20)
input bool   Usar_Noticias        = true;   // Quieres pausar el robot en horario de noticias?
input int    Noticias_Inicio      = 13;   // A que hora quieres que inicie la pausa?
input int    Noticias_Min_Ini     = 25;   // A que minuto quieres que inicie la pausa?
input int    Noticias_Fin         = 14;   // A que hora quieres que termine la pausa?
input int    Noticias_Min_Fin     = 0;   // A que minuto quieres que termine la pausa?

input group "==  AVANZADO (SOLO PRO)  =="
input bool   Usar_EMA_Filter      = true;    // [SOLO PRO] Filtro de tendencia adaptativo
input int    EMA_Fast             = 50;   // EMA rapida (media corta, ej. 50)
input int    EMA_Slow             = 200;   // EMA lenta (media larga, ej. 200)
input ENUM_TIMEFRAMES EMA_TF      = PERIOD_H1;   // En que temporalidad mide la tendencia?
input double EMA_Sep_Extrema      = 0.3;   // Separacion minima de EMAs para filtrar por tendencia (%)
input bool   Usar_Filtro_ADX      = true;  // No operar en el giro/acumulacion (filtro ADX)?
input int    ADX_Periodo          = 14;    // Periodo del ADX
input ENUM_TIMEFRAMES ADX_TF      = PERIOD_H1;  // En que temporalidad mide la fuerza de tendencia?
input double ADX_Minimo           = 25.0;  // Solo opera si el ADX supera este valor (25 = hay tendencia)
input bool   Usar_Compuesto       = true;    // [SOLO PRO] Dimensionamiento automatico de lote (0.01 por cada 100)
input double Compuesto_Pct        = 1.0;     // Multiplicador del compuesto (1.0 = 0.01 por cada 100)

input group "==  PERSONALIZACION  =="
input string Cliente_Nombre       = "Leonardo";   // Como te llamas? (para saludarte en el panel)
input int    Tema_Color           = 0;   // Que color prefieres? 0=Dorado 1=Plata 2=Azul 3=Verde 4=Rosa
enum ERiskProfile { MANUAL=0, CONSERVADOR=1, BALANCEADO=2, AGRESIVO=3 };
input ERiskProfile Perfil_Riesgo  = MANUAL;   // Que perfil? 0=Manual 1=Conservador 2=Balanceado 3=Agresivo
input int    Mascota              = 0;   // Que personaje quieres? 0=Toro 1=Lobo 2=Fenix
input int    Panel_Tamano         = 0;   // Que tamano de panel? 0=Laptop 1=Normal 2=Grande
input bool   Sonidos_Activos      = true;   // Quieres sonidos al abrir y cerrar operaciones?
input bool   Mostrar_Manual_Inicio= false;  // Quieres ver el manual al arrancar? (false en tester)
input bool   Mostrar_Ajustes      = true;   // Quieres ver la verificacion de ajustes al iniciar?

input group "==  NOTIFICACIONES  =="
input bool   Alertas_Movil        = true;   // Quieres recibir avisos en tu celular?

// ---- Parametros internos del motor (fijos, no se muestran en Inputs) ----
long   InpMagic            = 20260001;
int    InpSlippagePts      = 30;
bool   InpOnePositionOnly  = true;
int    InpRSIPeriod        = 14;
int    InpCCIPeriod        = 14;
int    InpATRPeriod        = 14;
int    InpEMASlow          = 100;
double InpPriorUp          = 0.50;
double InpThreshold        = 0.62;
double InpW_RSI            = 1.10;
double InpW_CCI            = 0.70;
double InpW_Slope          = 0.60;
double InpW_Return         = 0.50;
double InpW_Trend          = 0.40;
bool   InpUseRSIConfirm    = true;
double InpRSI_LongMax      = 55.0;
double InpRSI_ShortMin     = 45.0;
bool   InpUseAntiExtremos  = true;
bool   InpUseVolGate       = true;
double InpATRMinPts        = 80.0;
double InpATRMaxPts        = 900.0;
enum ERiskMode { RISK_FIXED_LOT=0, RISK_PERCENT=1 };
ERiskMode InpRiskMode      = RISK_FIXED_LOT; // .set usa StartingLots (lote fijo)
double InpRiskPercent      = 0.5;
double InpSL_ATR           = 2.0;
double InpTP_R             = 1.5;
bool   InpShieldCloseAll   = true;
enum EBEMode { BE_POR_PCT_TP=0, BE_POR_ATR=1 };
EBEMode InpBEMode          = BE_POR_PCT_TP;
double InpBE_ATR           = 1.0;
double InpBE_OffsetPts     = 20.0;
double InpTrail_MinATR     = 0.3;
bool   InpUseLayers        = false;
int    InpMaxLayers        = 3;
double InpLayerStepATR     = 1.0;
double InpLayerLotFactor   = 1.0;
bool   InpShowPanel        = true;
bool   InpShowSplash       = true;
int    InpPanelX           = 12;
int    InpPanelY           = 24;

//====================================================================
//  GLOBALES
//====================================================================
CTrade   trade;
int      hRSI=INVALID_HANDLE, hCCI=INVALID_HANDLE, hATR=INVALID_HANDLE, hEMA=INVALID_HANDLE;
int      hATRsma=INVALID_HANDLE;   // SMA(100) del ATR para el ratio de volatilidad
int      hADX=INVALID_HANDLE;      // ADX para el filtro de tendencia/giro
int      hEMAf=INVALID_HANDLE, hEMAs=INVALID_HANDLE;   // filtro de tendencia
datetime g_lastBarTime=0;
int      g_dayStamp=-1;
double   g_dayStartBal=0.0;
bool     g_shieldTripped=false;
int      g_lossStreak=0;         // perdidas seguidas (por PnL real)
bool     g_breakerTripped=false; // freno por perdidas seguidas
bool     g_objTripped=false;
string   g_sym;

bool     g_trailOn, g_beOn, g_shieldOn, g_paused;

// Valores efectivos (segun perfil)
double   g_shieldMax, g_riskPct, g_objetivoPct, g_bePct;
int      g_maxLayers;
bool     g_useLayers, g_usePercent;
ERiskProfile g_profile;   // perfil activo (cambiable desde el panel)

// Panel
string   PFX = "bg_";
double   g_lastP=0.0, g_lastRSI=0.0, g_lastCCI=0.0;
double   g_lastSetup=0.0, g_lastVol=0.0, g_lastSes=0.0, g_lastSpd=0.0; // factores INTEL
int      g_activeTab=0;
bool     g_use24, g_useNY, g_useAsia, g_useLon, g_useGMT;
bool     g_useObjetivo, g_useSpreadF, g_useMargin, g_useNews;
int      g_tutStep=0, g_faqIdx=0;
bool     g_panelHidden=false;
int      g_lastChartW=0;
int      MANUAL_PAGS=16;
int      g_manualPag=0;      // 0..15
bool     g_manualOpen=true;
int      g_splashTick=0;
bool     g_splashOn=true;
int      PAD, INL, INR;
int      g_panelBottom=0;
string   g_diagText="";
datetime g_diagTime=0;
double   g_stWeek=0, g_stMonth=0, g_stBestDay=0;
string   g_stBestDate="";
int      g_stPosDays=0, g_stMaxStreak=0;
datetime g_stLastCalc=0;

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym = _Symbol;
   trade.SetExpertMagicNumber(InpMagic);   // Identifier queda informativo
   trade.SetDeviationInPoints(InpSlippagePts);
   trade.SetTypeFillingBySymbol(g_sym);

   hRSI=iRSI(g_sym,PERIOD_CURRENT,InpRSIPeriod,PRICE_CLOSE);
   hCCI=iCCI(g_sym,PERIOD_CURRENT,InpCCIPeriod,PRICE_TYPICAL);
   hATR=iATR(g_sym,PERIOD_CURRENT,InpATRPeriod);
   hATRsma=iMA(g_sym,PERIOD_CURRENT,100,0,MODE_SMA,hATR);   // media del ATR (para el ratio)
   hADX=iADX(g_sym,ADX_TF,ADX_Periodo);                     // fuerza de tendencia (filtro de giro)
   hEMA=iMA (g_sym,PERIOD_CURRENT,InpEMASlow,0,MODE_EMA,PRICE_CLOSE);
   hEMAf=iMA(g_sym,EMA_TF,EMA_Fast,0,MODE_EMA,PRICE_CLOSE);
   hEMAs=iMA(g_sym,EMA_TF,EMA_Slow,0,MODE_EMA,PRICE_CLOSE);
   if(hRSI==INVALID_HANDLE||hCCI==INVALID_HANDLE||hATR==INVALID_HANDLE||hEMA==INVALID_HANDLE)
      return(INIT_FAILED);

   g_trailOn=Usar_Trailing; g_beOn=Usar_Breakeven; g_shieldOn=Usar_Shield; g_paused=false;
   g_profile=Perfil_Riesgo;
   g_manualOpen=Mostrar_Manual_Inicio;
   g_useGMT=!Usar_Hora_Local;
   g_use24=Operar_24H; g_useNY=Sesion_NuevaYork; g_useLon=Sesion_Londres; g_useAsia=Sesion_Asia;
   g_useObjetivo=Usar_Objetivo; g_useSpreadF=Usar_Spread_Max; g_useMargin=Usar_Margen; g_useNews=Usar_Noticias;
   ApplyProfile();
   ResetDay();

   if(InpShowPanel && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)))
   {
      CreatePanel();
   }
   if(InpShowSplash && !MQLInfoInteger(MQL_TESTER))
   {
      CreateSplash();
      EventSetMillisecondTimer(150);
   }
   else if(!MQLInfoInteger(MQL_TESTER))
   {
      if(Mostrar_Ajustes) CreateAjustes();
      else if(Mostrar_Manual_Inicio && g_manualOpen) CreateManual();
   }
   RefreshPanel();
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(hRSI!=INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hCCI!=INVALID_HANDLE) IndicatorRelease(hCCI);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   if(hATRsma!=INVALID_HANDLE) IndicatorRelease(hATRsma);
   if(hADX!=INVALID_HANDLE) IndicatorRelease(hADX);
   if(hEMA!=INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hEMAf!=INVALID_HANDLE) IndicatorRelease(hEMAf);
   if(hEMAs!=INVALID_HANDLE) IndicatorRelease(hEMAs);
   ObjectsDeleteAll(0, PFX);
   ObjectsDeleteAll(0, "bgman_");
   ObjectsDeleteAll(0, "bgspl_");
   ObjectsDeleteAll(0, "bgset_");
   Comment("");
}

// Animacion del splash de arranque
void OnTimer()
{
   if(!g_splashOn){ EventKillTimer(); return; }
   g_splashTick++;
   RenderSplash();
   ChartRedraw();
   if(g_splashTick>=20)   // ~3 segundos
   {
      CloseSplash();
      EventKillTimer();
      if(Mostrar_Ajustes) CreateAjustes();
      else if(Mostrar_Manual_Inicio && g_manualOpen) CreateManual();
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDayAndShield();
   ManagePositions();
   RefreshPanel();

   if(g_shieldOn && g_shieldTripped) return;
   if(g_objTripped) return;
   if(g_breakerTripped) return;
   if(g_paused) return;

   datetime bt=iTime(g_sym,PERIOD_CURRENT,0);
   if(bt==g_lastBarTime) return;
   g_lastBarTime=bt;

   if(!InSession()) return;

   double atrPts=GetATR()/_Point;
   if(InpUseVolGate && (atrPts<InpATRMinPts || atrPts>InpATRMaxPts)) return;

   double pUp=ComputePosteriorUp();
   double rsiNow=GetRSI(0), cciNow=GetCCI(0);
   g_lastP=pUp; g_lastRSI=rsiNow; g_lastCCI=cciNow;
   ComputeConfidence(pUp);

   int nBase=CountPositions();
   bool goLong =(pUp>=InpThreshold);
   bool goShort=(pUp<=1.0-InpThreshold);
   if(!EMAAllows(true))  goLong=false;    // solo comprar a favor de la tendencia
   if(!EMAAllows(false)) goShort=false;   // solo vender a favor de la tendencia
   if(InpUseRSIConfirm)
   {
      if(rsiNow>InpRSI_LongMax)  goLong=false;
      if(rsiNow<InpRSI_ShortMin) goShort=false;
   }
   if(InpUseAntiExtremos)
   {
      if(rsiNow>75.0 && cciNow>150.0)  goLong=false;
      if(rsiNow<25.0 && cciNow<-150.0) goShort=false;
   }

   if(InpOnePositionOnly && nBase>0 && !g_useLayers) return;
   if(!ADXAllows()) return;   // sin tendencia (ADX bajo): no operar en el giro/acumulacion
   if(!FiltrosOK()) return;
   if(nBase==0)
   {
      if(goLong)  OpenTrade(ORDER_TYPE_BUY);
      else if(goShort) OpenTrade(ORDER_TYPE_SELL);
   }
   else if(g_useLayers) TryAddLayer(pUp);
}

//====================================================================
//  PERFILES (numeros de la guia straderShop)
//====================================================================
void ApplyProfile()
{
   g_shieldMax = Shield_Pct; g_riskPct=InpRiskPercent;
   g_maxLayers = InpMaxLayers; g_useLayers=InpUseLayers;
   g_usePercent=(InpRiskMode==RISK_PERCENT);
   g_objetivoPct=0.0; g_bePct=BE_Activacion;

   switch(g_profile)
   {
      case CONSERVADOR: g_shieldMax=3.0; g_riskPct=0.5; g_useLayers=true; g_maxLayers=6;
                        g_usePercent=true; g_objetivoPct=2.0;  g_bePct=70.0; break;
      case BALANCEADO:  g_shieldMax=4.0; g_riskPct=1.0; g_useLayers=true; g_maxLayers=10;
                        g_usePercent=true; g_objetivoPct=3.0;  g_bePct=80.0; break;
      case AGRESIVO:    g_shieldMax=6.0; g_riskPct=1.8; g_useLayers=true; g_maxLayers=15;
                        g_usePercent=true; g_objetivoPct=5.0;  g_bePct=80.0; break;
      default: break; // MANUAL
   }
}
string ProfileName()
{
   switch(g_profile){ case CONSERVADOR:return "Conservador"; case BALANCEADO:return "Balanceado";
                       case AGRESIVO:return "Agresivo"; default:return "Manual"; }
}

//====================================================================
//  MOTOR BAYESIANO (RSI + CCI, log-odds)
//====================================================================
double ComputePosteriorUp()
{
   double atr=GetATR(); if(atr<=0) atr=_Point;
   double rsiNow=GetRSI(0), rsiPrev=GetRSI(1), cci=GetCCI(0), ema=GetEMA();
   double c=iClose(g_sym,PERIOD_CURRENT,1), o=iOpen(g_sym,PERIOD_CURRENT,1);

   double sRSI  =Clip((50.0-rsiNow)/50.0,-1,1);
   double sCCI  =Clip((-cci)/150.0,-1,1);
   double sSlope=Clip((rsiNow-rsiPrev)/25.0,-1,1);
   double sRet  =Clip((c-o)/atr,-1,1);
   double sTrend=Clip((c-ema)/atr,-1,1);

   double logit=Logit(InpPriorUp)+InpW_RSI*sRSI+InpW_CCI*sCCI
               +InpW_Slope*sSlope+InpW_Return*sRet+InpW_Trend*sTrend;
   return Sigmoid(logit);
}
// Confianza (INTEL): setup 40 + volatilidad 30 + sesion 15 + spread 15
void ComputeConfidence(double pUp)
{
   double setup = MathAbs(pUp-0.5)*2.0;                 // 0..1 fuerza de la señal
   double atrPts= GetATR()/_Point;
   double volOk = (atrPts>=InpATRMinPts && atrPts<=InpATRMaxPts)?1.0:0.0;
   double sesOk = InSession()?1.0:0.0;
   double spread= (SymbolInfoDouble(g_sym,SYMBOL_ASK)-SymbolInfoDouble(g_sym,SYMBOL_BID))/_Point;
   double spdOk = (spread<=InpATRMinPts*0.5)?1.0:MathMax(0.0,1.0-spread/(InpATRMinPts));
   g_lastSetup=setup; g_lastVol=volOk; g_lastSes=sesOk; g_lastSpd=spdOk;
}
double Confidence()
{
   double c=0.40*g_lastSetup+0.30*g_lastVol+0.15*g_lastSes+0.15*g_lastSpd;
   return Clip(0.05+c*0.90,0.05,0.95)*100.0; // rango 5..95%
}
double Sigmoid(double x){ return 1.0/(1.0+MathExp(-x)); }
double Logit(double p){ p=Clip(p,1e-6,1.0-1e-6); return MathLog(p/(1.0-p)); }
double Clip(double v,double lo,double hi){ return (v<lo?lo:(v>hi?hi:v)); }

// "Que esta haciendo el bot" — fiel al motor (probabilidad + estado real)
string EstadoBot()
{
   double thr=InpThreshold*100.0;
   double pUpPct=g_lastP*100.0;
   if(g_shieldOn && g_shieldTripped) return "Shield activo. Sin nuevas entradas hoy.";
   if(g_objTripped)                  return "Objetivo del dia cumplido. Cerrado hasta manana.";
   if(g_breakerTripped)              return StringFormat("Freno: %d SL/BE seguidos. Hasta manana.", g_lossStreak);
   if(g_paused)                      return "En pausa (manual).";
   if(!InSession())                  return "Fuera de sesion. Esperando "+ProximaSesion()+".";
   double atrPts=GetATR()/_Point;
   if(InpUseVolGate && (atrPts<InpATRMinPts||atrPts>InpATRMaxPts))
      return StringFormat("Volatilidad fuera de banda (ATR %.0f pts).",atrPts);
   double spr=(SymbolInfoDouble(g_sym,SYMBOL_ASK)-SymbolInfoDouble(g_sym,SYMBOL_BID))/_Point;
   if(g_useSpreadF && spr>Spread_Max)
      return StringFormat("Spread alto: %.0f pts (max %.0f). Esperando.",spr,Spread_Max);
   if(g_useMargin)
   {
      double ml=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(ml>0 && ml<Margen_Minimo) return StringFormat("Margen bajo: %.0f%% (min %.0f%%).",ml,Margen_Minimo);
   }
   if(g_useNews && InNewsWindow()) return "Ventana de noticias. En pausa.";
   if(Usar_Filtro_ADX)
   {
      double adx=GetADX();
      if(adx>0 && adx<ADX_Minimo)
         return StringFormat("Acumulacion (ADX %.0f < %.0f). Sin tendencia, no opera.", adx, ADX_Minimo);
   }
   if(CountPositions()>0)
      return (NetDirection()>0?"En LARGO. Gestionando SL/TP.":"En CORTO. Gestionando SL/TP.");
   // sin posicion: buscando
   if(pUpPct>=thr)        return StringFormat("Señal LONG lista (P=%.0f%%, req >=%.0f%%).",pUpPct,thr);
   if(pUpPct<=100.0-thr)  return StringFormat("Señal SELL lista (P=%.0f%%, req <=%.0f%%).",pUpPct,100.0-thr);
   if(pUpPct>=50.0)       return StringFormat("Buscando LONG (P=%.0f%%, necesita >=%.0f%%).",pUpPct,thr);
   return StringFormat("Buscando SELL (P=%.0f%%, necesita <=%.0f%%).",pUpPct,100.0-thr);
}
string ProximaSesion()
{
   datetime tt=g_useGMT?TimeGMT():TimeLocal();
   MqlDateTime s; TimeToStruct(tt,s); int h=s.hour;
   if(g_useAsia && h<Asia_Hora_Inicio) return "Asia";
   if(h<Londres_Hora_Inicio) return "Londres";
   if(h<NY_Hora_Inicio)     return "Nueva York";
   return "la proxima apertura";
}
// Score de calidad de operacion 0..100 (fuerza de señal + condiciones)
int ScoreOperacion()
{
   double s=0.55*g_lastSetup + 0.20*g_lastVol + 0.15*g_lastSes + 0.10*g_lastSpd;
   return (int)MathRound(Clip(s,0,1)*100.0);
}
string CalidadTxt(int score){ return (score>=70?"BUENA":(score>=45?"REGULAR":"BAJA")); }
string VolatilidadTxt()
{
   double atrPts=GetATR()/_Point;
   if(atrPts<InpATRMinPts) return "BAJA";
   if(atrPts>InpATRMaxPts) return "ALTA";
   return "NORMAL";
}

//====================================================================
//  INDICADORES
//====================================================================
double GetRSI(int shift){ double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(hRSI,0,shift+1,1,b)<1) return 50.0; return b[0]; }
double GetCCI(int shift){ double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(hCCI,0,shift+1,1,b)<1) return 0.0; return b[0]; }
double GetATR(){ double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(hATR,0,1,1,b)<1) return 0.0; return b[0]; }

// Ratio de volatilidad = ATR(14) / SMA(ATR(14),100)
double ATRRatio()
{
   double sma[]; ArraySetAsSeries(sma,true);
   if(CopyBuffer(hATRsma,0,1,1,sma)<1 || sma[0]<=0) return 1.0;
   return GetATR()/sma[0];
}
// Clasificacion: <0.70 BAJA, <1.30 MEDIA (normal), <1.70 ALTA, resto EXTREMA
string VolNivel(double r)
{
   if(r<0.70) return "BAJA";
   if(r<1.30) return "MEDIA";
   if(r<1.70) return "ALTA";
   return "EXTREMA";
}

// Filtro ADX: fuerza de tendencia. ADX bajo = mercado sin tendencia (acumulacion/giro)
double GetADX()
{
   double b[]; ArraySetAsSeries(b,true);
   if(hADX==INVALID_HANDLE || CopyBuffer(hADX,0,1,1,b)<1) return 0.0;
   return b[0];
}
bool ADXAllows()
{
   if(!Usar_Filtro_ADX) return true;
   double adx=GetADX();
   if(adx<=0) return true;             // sin datos: no bloquear
   return (adx >= ADX_Minimo);         // solo opera si hay tendencia (ADX alto)
}
double GetEMA(){ double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(hEMA,0,1,1,b)<1) return iClose(g_sym,PERIOD_CURRENT,1); return b[0]; }

// Filtro de tendencia adaptativo (dos EMAs en EMA_TF)
double EmaBuf(int h){ double b[]; ArraySetAsSeries(b,true);
   if(h==INVALID_HANDLE || CopyBuffer(h,0,1,1,b)<1) return 0.0; return b[0]; }
bool EMAAllows(bool isLong)
{
   if(!Usar_EMA_Filter) return true;
   double f=EmaBuf(hEMAf), s=EmaBuf(hEMAs);
   if(f<=0 || s<=0) return true;                       // sin datos: no bloquear
   double price=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double sepPct=(price>0)? (f-s)/price*100.0 : 0.0;   // con signo: + alcista, - bajista
   // Zona neutral: si las EMAs estan muy juntas (sin tendencia clara) no filtra
   if(MathAbs(sepPct) < EMA_Sep_Extrema) return true;
   // Tendencia clara: solo permite entradas a favor
   return isLong ? (sepPct>0) : (sepPct<0);
}

//====================================================================
//  SESIONES
//====================================================================
string SessionName()
{
   if(g_use24) return "24 horas";
   datetime tt=g_useGMT?TimeGMT():TimeLocal();
   MqlDateTime s; TimeToStruct(tt,s); int h=s.hour;
   if(g_useNY   && EnVentana(h,NY_Hora_Inicio,NY_Hora_Cierre))           return "Nueva York";
   if(g_useLon  && EnVentana(h,Londres_Hora_Inicio,Londres_Hora_Cierre)) return "Londres";
   if(g_useAsia && EnVentana(h,Asia_Hora_Inicio,Asia_Hora_Cierre))       return "Asia/Tokyo";
   return "";
}
bool EnVentana(int h,int ini,int fin)
{
   if(ini==fin) return false;
   if(ini<fin)  return (h>=ini && h<fin);
   return (h>=ini || h<fin);   // cruza medianoche (ej. 19 -> 2)
}
bool InSession()
{
   if(g_use24) return true;
   return (SessionName()!="");
}

//====================================================================
//  APERTURA
//====================================================================
//====================================================================
//  REGISTRO DETALLADO DE OPERACIONES (log + CSV para analisis)
//====================================================================
void LogTrade(ENUM_ORDER_TYPE type,double price,double lot,double sl,double tp,double atr,double slDist,long posid)
{
   string dir =(type==ORDER_TYPE_BUY)?"BUY":"SELL";
   string ses =SessionName(); if(ses=="") ses="fuera-sesion";
   double slPts=slDist/_Point;
   double tpPts=MathAbs(tp-price)/_Point;
   double slPips=slPts/10.0;                 // aprox. pips en XAU (10 pts = 1 pip)
   double prob =g_lastP*100.0;
   int    score=ScoreOperacion();
   double conf =Confidence();
   double rsi  =GetRSI(0), cci=GetCCI(0);
   double atrP =atr/_Point;
   double emaF =EmaBuf(hEMAf), emaS=EmaBuf(hEMAs);
   string trend=(emaF>emaS?"ALCISTA":(emaF<emaS?"BAJISTA":"plano"));
   double sep  =(price>0? MathAbs(emaF-emaS)/price*100.0 : 0.0);
   double spr  =(SymbolInfoDouble(g_sym,SYMBOL_ASK)-SymbolInfoDouble(g_sym,SYMBOL_BID))/_Point;
   double vratio=ATRRatio();
   string vnivel=VolNivel(vratio);

   PrintFormat("[TRADE] %s %s | sesion=%s | vol=%s (ratio %.2f) | entrada=%.2f lote=%.2f | SL=%.2f (%.0f pts / %.1f pips) TP=%.2f (%.0f pts) | P=%.1f%% score=%d conf=%.0f%% | RSI=%.0f CCI=%.0f ATR=%.0f pts | EMA_f=%.2f EMA_s=%.2f (%s sep=%.2f%%) | spread=%.1f | perfil=%s",
      dir, g_sym, ses, vnivel, vratio, price, lot, sl, slPts, slPips, tp, tpPts, prob, score, conf, rsi, cci, atrP, emaF, emaS, trend, sep, spr, ProfileName());

   // CSV en MQL5\Files (o carpeta del Probador)
   string fn="BayesianGold_"+g_sym+"_trades.csv";
   int h=FileOpen(fn, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"fecha","hora","pos_id","dir","sesion","vol_nivel","atr_ratio","entrada","lote","sl","sl_pts","sl_pips",
                  "tp","tp_pts","prob_%","score","conf_%","rsi","cci","atr_pts",
                  "ema_fast","ema_slow","tendencia","sep_%","spread_pts","perfil");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,
      TimeToString(TimeCurrent(),TIME_DATE),
      TimeToString(TimeCurrent(),TIME_SECONDS),
      (string)posid,
      dir, ses, vnivel, DoubleToString(vratio,2),
      DoubleToString(price,2), DoubleToString(lot,2),
      DoubleToString(sl,2), DoubleToString(slPts,0), DoubleToString(slPips,1),
      DoubleToString(tp,2), DoubleToString(tpPts,0),
      DoubleToString(prob,1), (string)score, DoubleToString(conf,0),
      DoubleToString(rsi,0), DoubleToString(cci,0), DoubleToString(atrP,0),
      DoubleToString(emaF,2), DoubleToString(emaS,2), trend, DoubleToString(sep,2),
      DoubleToString(spr,1), ProfileName());
   FileClose(h);
}

// Registro al CIERRE de cada operacion (resultado, pips, duracion, motivo)
void LogClose(ulong dealTk)
{
   long   posid =HistoryDealGetInteger(dealTk,DEAL_POSITION_ID);
   long   dt    =HistoryDealGetInteger(dealTk,DEAL_TYPE);
   string dir   =(dt==DEAL_TYPE_SELL)?"BUY":"SELL";   // el OUT es opuesto a la posicion
   double exitP =HistoryDealGetDouble(dealTk,DEAL_PRICE);
   double vol   =HistoryDealGetDouble(dealTk,DEAL_VOLUME);
   double profit=HistoryDealGetDouble(dealTk,DEAL_PROFIT)+HistoryDealGetDouble(dealTk,DEAL_SWAP)+HistoryDealGetDouble(dealTk,DEAL_COMMISSION);
   datetime tOut=(datetime)HistoryDealGetInteger(dealTk,DEAL_TIME);
   long   reason=HistoryDealGetInteger(dealTk,DEAL_REASON);
   string motivo=(reason==DEAL_REASON_SL?"SL":(reason==DEAL_REASON_TP?"TP":(reason==DEAL_REASON_SO?"StopOut":"manual/otro")));

   double entry=0; datetime tIn=0;
   if(HistorySelectByPosition(posid))
   {
      int n=HistoryDealsTotal();
      for(int i=0;i<n;i++)
      {
         ulong d=HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(d,DEAL_POSITION_ID)!=posid) continue;
         if(HistoryDealGetInteger(d,DEAL_ENTRY)==DEAL_ENTRY_IN)
         { entry=HistoryDealGetDouble(d,DEAL_PRICE); tIn=(datetime)HistoryDealGetInteger(d,DEAL_TIME); }
      }
   }
   double pts =(entry>0)? ((dir=="BUY")?(exitP-entry):(entry-exitP))/_Point : 0.0;
   double pips=pts/10.0;
   int    durMin=(tIn>0)? (int)((tOut-tIn)/60) : 0;
   string ses =SessionName(); if(ses=="") ses="fuera-sesion";

   // Freno por rachas: cuenta SL real Y break-even (ambos cierran por "SL"); solo el TP reinicia
   if(motivo=="TP")
   {
      g_lossStreak=0;   // ganadora por Take Profit reinicia la racha
   }
   else
   {
      g_lossStreak++;   // SL o break-even suman
      if(Usar_FrenoRachas && Perdidas_Seguidas>0 && g_lossStreak>=Perdidas_Seguidas)
      {
         g_breakerTripped=true;
         PrintFormat("[FRENO] %d cierres sin ganar (SL/BE) seguidos. Sin nuevas entradas hasta manana.", g_lossStreak);
         if(Alertas_Movil)
            SendNotification(StringFormat("Bayesian FRENO: %d SL/BE seguidos. Pausado hasta manana.", g_lossStreak));
      }
   }

   PrintFormat("[CIERRE] %s %s pos=%s | entrada=%.2f salida=%.2f | %s%.0f pts (%.1f pips) | PnL=%.2f | dur=%d min | motivo=%s",
      dir, g_sym, (string)posid, entry, exitP, (pts>=0?"+":""), pts, pips, profit, durMin, motivo);

   if(Alertas_Movil)
      SendNotification(StringFormat("Bayesian CIERRE %s %s | %s%.0f pts | PnL %s%.2f | %s",
         dir, g_sym, (pts>=0?"+":""), pts, (profit>=0?"+":""), profit, motivo));

   string fn="BayesianGold_"+g_sym+"_cierres.csv";
   int h=FileOpen(fn, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"fecha","hora","pos_id","dir","entrada","salida","pnl_usd","pts","pips","dur_min","motivo","lote","sesion_cierre");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,
      TimeToString(tOut,TIME_DATE), TimeToString(tOut,TIME_SECONDS), (string)posid, dir,
      DoubleToString(entry,2), DoubleToString(exitP,2), DoubleToString(profit,2),
      DoubleToString(pts,0), DoubleToString(pips,1), (string)durMin, motivo,
      DoubleToString(vol,2), ses);
   FileClose(h);
}
// Se dispara en cada transaccion; registramos los cierres de este EA
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   ulong dealTk=trans.deal;
   if(dealTk==0 || !HistoryDealSelect(dealTk)) return;
   if(HistoryDealGetString(dealTk,DEAL_SYMBOL)!=g_sym) return;
   if(HistoryDealGetInteger(dealTk,DEAL_MAGIC)!=InpMagic) return;
   if(HistoryDealGetInteger(dealTk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   LogClose(dealTk);
}

void OpenTrade(ENUM_ORDER_TYPE type)
{
   double atr=GetATR(); if(atr<=0) return;
   double slDist=atr*InpSL_ATR;
   // Filtro: si el SL calculado es demasiado grande, no abrir esta operacion
   if(Max_SL_Puntos>0 && slDist/_Point > Max_SL_Puntos)
   {
      PrintFormat("[SKIP] SL %.0f pts supera el limite de %.0f pts. Operacion NO abierta.",
                  slDist/_Point, Max_SL_Puntos);
      return;
   }
   double tpDist=(TakeProfit>0? TakeProfit*_Point : slDist*InpTP_R);
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK), bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double price=(type==ORDER_TYPE_BUY)?ask:bid;
   double sl,tp;
   if(type==ORDER_TYPE_BUY){ sl=price-slDist; tp=price+tpDist; }
   else                    { sl=price+slDist; tp=price-tpDist; }
   sl=NormalizeStop(sl); tp=NormalizeStop(tp);
   double lot=CalcLot(slDist); if(lot<=0) return;
   bool ok;
   if(type==ORDER_TYPE_BUY) ok=trade.Buy(lot,g_sym,0.0,sl,tp,"Bayes base");
   else                     ok=trade.Sell(lot,g_sym,0.0,sl,tp,"Bayes base");
   if(ok)
   {
      string dir=(type==ORDER_TYPE_BUY)?"BUY":"SELL";
      if(Alertas_Movil)   SendNotification(StringFormat("Bayesian %s %s lote %.2f",dir,g_sym,lot));
      if(Sonidos_Activos) PlaySound("ok.wav");
      long posid=0;
      ulong dTk=trade.ResultDeal();
      if(dTk>0 && HistoryDealSelect(dTk)) posid=HistoryDealGetInteger(dTk,DEAL_POSITION_ID);
      LogTrade(type,price,lot,sl,tp,atr,slDist,posid);
   }
}
void TryAddLayer(double pUp)
{
   if(CountPositions()>=g_maxLayers) return;
   double atr=GetATR(); if(atr<=0) return;
   int dir=NetDirection(); if(dir==0) return;
   double lastEntry=LastEntryPrice(dir);
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK), bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   bool addLong =(dir>0&&pUp>=InpThreshold    &&(lastEntry-ask)>=InpLayerStepATR*atr);
   bool addShort=(dir<0&&pUp<=1.0-InpThreshold&&(bid-lastEntry)>=InpLayerStepATR*atr);
   double slDist=atr*InpSL_ATR;
   double mult=(int)Layer_Multiplier/10.0;                 // LM_10=1.0 ... LM_20=2.0
   int nCapa=CountPositions();                             // capa que se abrira (1 = 2da posicion)
   double lot=CalcLot(slDist)*InpLayerLotFactor*MathPow(mult,nCapa);
   if(lot<=0) return;
   if(addLong){ double sl=NormalizeStop(ask-slDist),tp=NormalizeStop(ask+slDist*InpTP_R);
                trade.Buy(lot,g_sym,0.0,sl,tp,"Bayes capa"); }
   else if(addShort){ double sl=NormalizeStop(bid+slDist),tp=NormalizeStop(bid-slDist*InpTP_R);
                trade.Sell(lot,g_sym,0.0,sl,tp,"Bayes capa"); }
}

//====================================================================
//  LOTE
//====================================================================
double CalcLot(double slDistPrice)
{
   if(!g_usePercent)
   {
      double lot=StartingLots;
      if(AutoCompound || Usar_Compuesto)
      {
         // 0.01 (StartingLots) por cada 100 de balance: 100->0.01, 200->0.02, 300->0.03...
         double steps=MathFloor(AccountInfoDouble(ACCOUNT_BALANCE)/100.0);
         if(steps<1) steps=1;
         lot=StartingLots*steps*Compuesto_Pct;
      }
      return NormalizeLot(lot);
   }
   double risk=AccountInfoDouble(ACCOUNT_BALANCE)*g_riskPct/100.0;
   double tv=SymbolInfoDouble(g_sym,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(g_sym,SYMBOL_TRADE_TICK_SIZE);
   if(ts<=0) return NormalizeLot(StartingLots);
   double lossPerLot=slDistPrice*(tv/ts);
   if(lossPerLot<=0) return NormalizeLot(StartingLots);
   return NormalizeLot(risk/lossPerLot);
}
double NormalizeLot(double lot)
{
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP); if(st<=0) st=0.01;
   lot=MathFloor(lot/st)*st; if(lot<mn) lot=mn; if(lot>mx) lot=mx;
   return NormalizeDouble(lot,2);
}
double NormalizeStop(double p){ return NormalizeDouble(p,(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS)); }

//====================================================================
//  GESTION: BE (por % al TP o ATR) + TRAILING (por % de ganancia)
//====================================================================
void ManagePositions()
{
   double atr=GetATR();
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=g_sym) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL), tp=PositionGetDouble(POSITION_TP);
      double bid=SymbolInfoDouble(g_sym,SYMBOL_BID), ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
      double newSL=sl;
      double minStop=(double)SymbolInfoInteger(g_sym,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
      double buffer =minStop+20*_Point;   // distancia minima del broker + margen
      double step   =10*_Point;           // paso minimo del trailing (evita spam)

      if(type==POSITION_TYPE_BUY)
      {
         double price=bid, gain=price-open;
         // Break-even
         if(g_beOn)
         {
            bool trig=false;
            if(InpBEMode==BE_POR_PCT_TP && tp>open)
               trig = (price >= open + (tp-open)*g_bePct/100.0);
            else
               trig = (gain >= InpBE_ATR*atr);
            if(trig){ double be=open+InpBE_OffsetPts*_Point; if(be>newSL) newSL=be; }
         }
         // Trailing por % de la ganancia. Arranca al recorrer Trailing_Activar% del camino al TP.
         bool trailOn=false;
         if(tp>open) trailOn = (price >= open + (tp-open)*Trailing_Activar/100.0);
         else        trailOn = (gain >= InpTrail_MinATR*atr);   // respaldo si no hay TP
         if(g_trailOn && trailOn)
         {
            double tr=open + gain*Trailing_Dist/100.0;
            if(tr>newSL) newSL=tr;
         }
         // solo si mejora de verdad Y respeta la distancia minima del broker
         if(newSL>=sl+step && newSL<=price-buffer)
            trade.PositionModify(tk,NormalizeStop(newSL),tp);
      }
      else if(type==POSITION_TYPE_SELL)
      {
         double price=ask, gain=open-price;
         if(g_beOn)
         {
            bool trig=false;
            if(InpBEMode==BE_POR_PCT_TP && tp<open && tp>0)
               trig = (price <= open - (open-tp)*g_bePct/100.0);
            else
               trig = (gain >= InpBE_ATR*atr);
            if(trig){ double be=open-InpBE_OffsetPts*_Point; if(sl==0||be<newSL) newSL=be; }
         }
         bool trailOnS=false;
         if(tp>0 && tp<open) trailOnS = (price <= open - (open-tp)*Trailing_Activar/100.0);
         else                trailOnS = (gain >= InpTrail_MinATR*atr);
         if(g_trailOn && trailOnS)
         {
            double tr=open - gain*Trailing_Dist/100.0;
            if(sl==0||tr<newSL) newSL=tr;
         }
         if((sl==0 || newSL<=sl-step) && newSL>=price+buffer)
            trade.PositionModify(tk,NormalizeStop(newSL),tp);
      }
   }
}

//====================================================================
//  SHIELD
//====================================================================
void ResetDay()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   g_dayStamp=t.day_of_year; g_dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE);
   g_shieldTripped=false;
   g_objTripped=false;
   g_lossStreak=0;
   g_breakerTripped=false;
}
void UpdateDayAndShield()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   if(t.day_of_year!=g_dayStamp) ResetDay();
   // Shield: stop-loss global diario
   if(g_shieldOn && !g_shieldTripped && DailyDDPct()>=g_shieldMax)
   {
      g_shieldTripped=true;
      if(InpShieldCloseAll) CloseAll();
   }
   // Objetivo de ganancia del dia: cierra TODO y no abre mas hoy
   if(g_useObjetivo && !g_objTripped && ObjetivoAlcanzado())
   {
      g_objTripped=true;
      CloseAll();
   }
}
// Manual: objetivo en USD (Objetivo_Diario). Perfiles: objetivo en % (g_objetivoPct).
bool ObjetivoAlcanzado()
{
   // Meta en % del balance (Manual usa Objetivo_Diario; perfiles usan g_objetivoPct)
   double meta=(g_profile==MANUAL)? Objetivo_Diario : g_objetivoPct;
   return (meta>0 && DailyGainPct()>=meta);
}

//====================================================================
//  UTILIDADES DE POSICION
//====================================================================
int CountPositions()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong tk=PositionGetTicket(i); if(!PositionSelectByTicket(tk)) continue;
     if(PositionGetString(POSITION_SYMBOL)==g_sym && PositionGetInteger(POSITION_MAGIC)==InpMagic) n++; }
   return n;
}
int NetDirection()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong tk=PositionGetTicket(i); if(!PositionSelectByTicket(tk)) continue;
     if(PositionGetString(POSITION_SYMBOL)!=g_sym) continue;
     if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
     return (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1; }
   return 0;
}
double LastEntryPrice(int dir)
{
   double best=(dir>0)?DBL_MAX:0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong tk=PositionGetTicket(i); if(!PositionSelectByTicket(tk)) continue;
     if(PositionGetString(POSITION_SYMBOL)!=g_sym) continue;
     if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
     double op=PositionGetDouble(POSITION_PRICE_OPEN);
     if(dir>0) best=MathMin(best,op); else best=MathMax(best,op); }
   return best;
}
void CloseAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong tk=PositionGetTicket(i); if(!PositionSelectByTicket(tk)) continue;
     if(PositionGetString(POSITION_SYMBOL)!=g_sym) continue;
     if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
     trade.PositionClose(tk); }
}
void CloseInProfit()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong tk=PositionGetTicket(i); if(!PositionSelectByTicket(tk)) continue;
     if(PositionGetString(POSITION_SYMBOL)!=g_sym) continue;
     if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
     if(PositionGetDouble(POSITION_PROFIT)>0) trade.PositionClose(tk); }
}
void CountWL(int &wins,int &losses)
{
   wins=0; losses=0;
   MqlDateTime t; TimeToStruct(TimeCurrent(),t); t.hour=0; t.min=0; t.sec=0;
   datetime dayStart=StructToTime(t);
   if(!HistorySelect(dayStart, TimeCurrent()+60)) return;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
   {
      ulong tk=HistoryDealGetTicket(i);
      if(HistoryDealGetString(tk,DEAL_SYMBOL)!=g_sym) continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=InpMagic) continue;
      if(HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double p=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_COMMISSION);
      if(p>=0) wins++; else losses++;
   }
}
// Ganancia realizada hoy (deals cerrados desde medianoche)
double RealizedToday()
{
   double realized=0.0;
   MqlDateTime t; TimeToStruct(TimeCurrent(),t); t.hour=0; t.min=0; t.sec=0;
   datetime dayStart=StructToTime(t);
   if(HistorySelect(dayStart, TimeCurrent()+60))
   {
      int total=HistoryDealsTotal();
      for(int i=0;i<total;i++)
      {
         ulong tk=HistoryDealGetTicket(i);
         if(HistoryDealGetString(tk,DEAL_SYMBOL)!=g_sym) continue;
         if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=InpMagic) continue;
         realized+=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_COMMISSION);
      }
   }
   return realized;
}
// Flotante actual (posiciones abiertas de este EA)
double FloatingPnL()
{
   double floatp=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong tk=PositionGetTicket(i); if(!PositionSelectByTicket(tk)) continue;
     if(PositionGetString(POSITION_SYMBOL)!=g_sym) continue;
     if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
     floatp+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP); }
   return floatp;
}
// Ganancia del dia = realizado hoy + flotante
double GananciaHoy(){ return RealizedToday()+FloatingPnL(); }
// Balance real al inicio del dia (medianoche), reconstruido:
//   balance_actual = balance_medianoche + realizado_hoy
double DayStartBalance()
{
   double b=AccountInfoDouble(ACCOUNT_BALANCE)-RealizedToday();
   return (b>0? b : AccountInfoDouble(ACCOUNT_BALANCE));
}
// Perdida acumulada del dia en % (0 si el dia va en positivo)
double DailyDDPct()
{
   double dstart=DayStartBalance();
   if(dstart<=0) return 0.0;
   return MathMax(0.0, -GananciaHoy()/dstart*100.0);
}
double DailyGainPct()
{
   double d=DayStartBalance();
   return (d>0)? GananciaHoy()/d*100.0 : 0.0;
}
bool InNewsWindow()
{
   int ini=Noticias_Inicio*60+Noticias_Min_Ini;
   int fin=Noticias_Fin*60+Noticias_Min_Fin;
   if(ini==fin) return false;
   datetime tt=g_useGMT?TimeGMT():TimeLocal();
   MqlDateTime s; TimeToStruct(tt,s);
   int now=s.hour*60+s.min;
   if(ini<fin) return (now>=ini && now<fin);
   return (now>=ini || now<fin);   // ventana que cruza medianoche
}
// Filtros Pro: true si se puede abrir una nueva operacion
bool FiltrosOK()
{
   if(CountPositions()>=MaxTrades) return false;
   double spr=(SymbolInfoDouble(g_sym,SYMBOL_ASK)-SymbolInfoDouble(g_sym,SYMBOL_BID))/_Point;
   if(g_useSpreadF && spr>Spread_Max) return false;
   if(g_useMargin)
   {
      double ml=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(ml>0 && ml<Margen_Minimo) return false;
   }
   if(g_useNews && InNewsWindow()) return false;
   return true;
}

//====================================================================
//  DIAGNOSTICAR (7 puntos)
//====================================================================
void RunDiagnostico()
{
   bool autotr=(bool)MQLInfoInteger(MQL_TRADE_ALLOWED) && (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool simbolo=(StringFind(g_sym,"XAU")>=0 || StringFind(g_sym,"GOLD")>=0);
   bool conn=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   bool ses=InSession();
   double spread=(SymbolInfoDouble(g_sym,SYMBOL_ASK)-SymbolInfoDouble(g_sym,SYMBOL_BID))/_Point;
   bool spreadOk=(spread<=Spread_Max);

   string s="DIAGNOSTICO BAYESIAN:\n\n";
   if(autotr) s+="[V] AutoTrading: ACTIVO\n";
   else       s+="[X] AutoTrading: DESACTIVADO\n    - Solucion: presiona el boton verde 'AutoTrading'\n";
   s+=(simbolo?"[V] Simbolo: "+g_sym+" (correcto)\n"
             :"[X] Simbolo: "+g_sym+"\n    - Solucion: usa un grafico de XAUUSD/GOLD\n");
   s+=(conn?"[V] Conexion al broker: OK\n":"[X] Conexion al broker: SIN CONEXION\n");
   s+=StringFormat("[V] Equity: $%.2f\n",eq);
   s+=(ses?"[V] Sesion: ACTIVA\n":"[!] Sesion: fuera de horario\n    - El bot espera su ventana\n");
   s+=(spreadOk?StringFormat("[V] Spread: %.1f pts\n",spread)
              :StringFormat("[!] Spread alto: %.1f pts\n    - El bot espera mejores condiciones\n",spread));
   s+="[V] Licencia: VIP VITALICIA\n";
   s+="\n==============================\n";
   bool critico=(!autotr || !conn || !simbolo);
   if(critico)              s+="RESULTADO: REVISAR ANTES DE OPERAR";
   else if(ses && spreadOk) s+="RESULTADO: TODO LISTO PARA OPERAR";
   else                     s+="RESULTADO: LISTO (esperando condiciones)";

   g_diagText=s; g_diagTime=TimeCurrent();
   Print(s);
   Alert(s);
}

//====================================================================
//  PANEL
//====================================================================
#define COL_BG      C'16,18,24'
#define COL_CARD    C'22,25,33'
#define COL_BORDER  C'212,175,55'
#define COL_GOLD    C'240,190,70'
#define COL_GREEN   C'64,200,140'
#define COL_BLUE    C'88,170,255'
#define COL_GRAY    C'130,140,152'
#define COL_WHITE   C'225,228,234'
#define COL_TRACK   C'40,44,54'
#define COL_RED     C'220,90,90'
#define P_W   300

void CreatePanel()
{
   int X=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-P_W-InpPanelX;
   if(X<10) X=10;
   int Y=InpPanelY;
   PAD=16; INL=X+PAD; INR=X+P_W-PAD;
   int y=Y+PAD;

   Rect(PFX+"bg", X, Y, P_W, 680, COL_BG, COL_BORDER, false);
   Btn(PFX+"min","—", X+5, Y+5, 20, 18, 10);
   Lbl(PFX+"title","BAYESIAN STRATEGY", INL+16, y, COL_GOLD, 12, "Arial Black"); y+=28;
   Lbl(PFX+"hola","Hola, "+Cliente_Nombre, INL, y, COL_GRAY, 8); y+=18;

   Rect(PFX+"vip", INL, y-1, 34, 16, COL_GOLD, COL_GOLD, false);
   Lbl(PFX+"viptx","VIP", INL+7, y, C'20,20,20', 8, "Arial Black");
   Lbl(PFX+"lic","VITALICIA", INL+42, y, COL_WHITE, 9, "Arial Bold");
   Lbl(PFX+"sess","FUERA SES", INR, y, COL_GRAY, 9, "Arial Bold", ANCHOR_RIGHT_UPPER); y+=22;
   Lbl(PFX+"sub","PRO "+g_sym+" M5   "+BG_VERSION, INL, y, COL_GRAY, 9);
   Lbl(PFX+"clock","--:--", INR, y, COL_BLUE, 10, "Arial Bold", ANCHOR_RIGHT_UPPER); y+=26;

   string tabs[6]={"CTA","CFG","STAT","INTEL","HIST","?"};
   int tw=(P_W-2*PAD-5*4)/6;
   for(int i=0;i<6;i++) Btn(PFX+"tab"+(string)i, tabs[i], INL+i*(tw+4), y, tw, 22, 8);
   ObjectSetInteger(0,PFX+"tab3",OBJPROP_BORDER_COLOR,COL_RED);   // INTEL con borde rojo
   ObjectSetInteger(0,PFX+"tab4",OBJPROP_BORDER_COLOR,COL_GOLD);  // HIST con borde amarillo
   y+=32;
   int pageY=y;

   // CTA
   string P=PFX+"cta_"; y=pageY;
   Sec(P+"s_bal","BALANCE", y); y+=20;
   Row(P,"eq","EQUITY", y); y+=22; Row(P,"bal","BALANCE", y); y+=22;
   Row(P,"mfree","MARGEN LIBRE", y); y+=22; Row(P,"mlvl","MARGEN %", y); y+=28;
   Sec(P+"s_ops","OPERACIONES", y); y+=20;
   Row(P,"caps","Capas abiertas", y); y+=22;
   Rect(P+"gainbg", INL-4, y-2, P_W-2*PAD+8, 20, C'18,30,24', C'40,70,55', false);
   ObjectSetInteger(0,P+"gainbg",OBJPROP_BACK,true);
   Row(P,"gain","GANANCIA HOY", y); y+=22;
   Row(P,"spread","SPREAD", y); y+=28;
   Sec(P+"s_shd","SHIELD HOY", y); y+=20; Row(P,"dd","Perdida acum", y); y+=22;
   Rect(P+"barbg", INL, y, P_W-2*PAD, 7, COL_TRACK, COL_TRACK, false);
   Rect(P+"barfl", INL, y, 1, 7, COL_GREEN, COL_GREEN, false); y+=24;
   Sec(P+"s_stat","ESTADISTICAS HOY", y); y+=20;
   Row(P,"wl","W / L", y); y+=22; Row(P,"be","BREAKEVEN", y); y+=26;
   int ctaBottom=y;

   // Botones de accion (SOLO en CTA)
   int bw=(P_W-2*PAD-2*8)/3, bh=32; y=ctaBottom+4;
   Btn(PFX+"btnTRAIL","TRAIL", INL, y, bw, bh, 9);
   Btn(PFX+"btnBE","BE", INL+(bw+8), y, bw, bh, 9);
   Btn(PFX+"btnSECURE","ASEGURAR", INL+2*(bw+8), y, bw, bh, 9); y+=bh+8;
   Btn(PFX+"btnCLOSE","CERRAR", INL, y, bw, bh, 9);
   Btn(PFX+"btnSHIELD","SHIELD", INL+(bw+8), y, bw, bh, 9);
   Btn(PFX+"btnPAUSE","PAUSAR", INL+2*(bw+8), y, bw, bh, 9); y+=bh;
   int mb=y;

   // CFG (toggles V/X)
   P=PFX+"cfg_"; y=pageY;
   Lbl(P+"gs","SESIONES", INL, y, COL_GOLD, 8, "Arial Bold"); y+=18;
   ToggleRow(P,"t24","24 HORAS", y); y+=22;
   ToggleRow(P,"tny","NUEVA YORK", y); y+=22;
   ToggleRow(P,"tas","ASIA", y); y+=22;
   ToggleRow(P,"tlo","LONDRES", y); y+=24;
   Lbl(P+"gp","PROTECCION", INL, y, COL_GOLD, 8, "Arial Bold"); y+=18;
   ToggleRow(P,"tob","OBJETIVO", y); y+=22;
   ToggleRow(P,"tbe","BREAKEVEN", y); y+=22;
   ToggleRow(P,"tsh","SHIELD SL", y); y+=24;
   Lbl(P+"gf","FILTROS PRO", INL, y, COL_GOLD, 8, "Arial Bold"); y+=18;
   ToggleRow(P,"tsp","FILTRO SPREAD", y); y+=22;
   ToggleRow(P,"tmg","VALIDAR MARGEN", y); y+=22;
   ToggleRow(P,"tnw","NOTICIAS", y); y+=24;
   Lbl(P+"pl","PERFIL DE RIESGO", INL, y, COL_GOLD, 8, "Arial Bold"); y+=18;
   int pbw=(P_W-2*PAD-3*4)/4;
   Btn(P+"pMAN","MAN",  INL,           y, pbw, 22, 8);
   Btn(P+"pCONS","CONS",INL+(pbw+4),   y, pbw, 22, 8);
   Btn(P+"pBAL","BAL",  INL+2*(pbw+4), y, pbw, 22, 8);
   Btn(P+"pAGR","AGR",  INL+3*(pbw+4), y, pbw, 22, 8); y+=26;
   Lbl(P+"pm","Manual: configura tu propio riesgo", INL, y, C'120,110,60', 7); y+=16;
   Btn(P+"params","ABRIR PARAMETROS (F7)", INL, y, P_W-2*PAD, 24, 8); y+=30;
   mb=MathMax(mb,y);

   // STAT
   P=PFX+"stat_"; y=pageY;
   Sec(P+"se","ESTADISTICAS", y); y+=20;
   Row(P,"wl","W / L hoy", y); y+=22;
   Row(P,"wr","Winrate", y); y+=22;
   Row(P,"gain","Ganancia hoy", y); y+=22;
   Row(P,"npos","Posiciones", y); y+=22;
   Row(P,"prob","P(subida)", y); y+=22;
   Row(P,"osc","RSI / CCI", y); y+=26;
   Sec(P+"sp","PERIODOS", y); y+=20;
   Row(P,"hoy","Hoy", y); y+=22;
   Row(P,"sem","Esta semana", y); y+=22;
   Row(P,"mes","Este mes", y); y+=26;
   Sec(P+"sr","RECORD", y); y+=20;
   Row(P,"best","Mejor dia", y); y+=22;
   Row(P,"bestd","Fecha", y); y+=26;
   Sec(P+"sra","RACHA", y); y+=20;
   Row(P,"pos","Dias positivos", y); y+=22;
   Row(P,"max","Maxima", y); y+=26;
   Sec(P+"sm","MISIONES HOY", y);
   Lbl(P+"mcount","0 / 3", INR, y, COL_RED, 9, "Arial Bold", ANCHOR_RIGHT_UPPER); y+=20;
   Lbl(P+"m0","", INL, y, COL_WHITE, 8); y+=17;
   Lbl(P+"m1","", INL, y, COL_WHITE, 8); y+=17;
   Lbl(P+"m2","", INL, y, COL_WHITE, 8); y+=17;
   mb=MathMax(mb,y);

   // INTEL
   P=PFX+"intel_"; y=pageY;
   Lbl(P+"qh","QUE ESTA HACIENDO EL BOT", INL, y, COL_GOLD, 8, "Arial Bold"); y+=16;
   Lbl(P+"live","...", INL, y, COL_GREEN, 9, "Arial Bold"); y+=24;
   Sec(P+"s1","CALIDAD DE OPERACION", y); y+=18;
   Row(P,"score","Score", y); y+=20;
   Row(P,"estado","Estado", y); y+=16;
   BarRow(P,"scorebar","", y); y+=24;
   Sec(P+"s2","TERMOMETRO", y); y+=18;
   Row(P,"vol","Volatilidad", y); y+=26;
   Sec(P+"s3","PROXIMA ENTRADA", y); y+=18;
   Row(P,"next","Estimada", y); y+=20;
   Row(P,"nhoy","Entradas hoy", y); y+=26;
   Sec(P+"s4","CONFIANZA DEL TRADE", y); y+=18;
   Row(P,"conf","Probabilidad", y); y+=20;
   Row(P,"cstado","Estado", y); y+=16;
   BarRow(P,"confbar","", y); y+=16;
   mb=MathMax(mb,y);

   // HIST (trades de hoy)
   P=PFX+"hist_"; y=pageY;
   Lbl(P+"h","TRADES DE HOY", INL, y, COL_GOLD, 8, "Arial Bold"); y+=20;
   Lbl(P+"cd","Dir", INL, y, COL_GRAY, 8, "Arial Bold");
   Lbl(P+"ch","Hora", INL+70, y, COL_GRAY, 8, "Arial Bold");
   Lbl(P+"cp","Pts", INL+150, y, COL_GRAY, 8, "Arial Bold");
   Lbl(P+"cl","P&L", INR, y, COL_GRAY, 8, "Arial Bold", ANCHOR_RIGHT_UPPER); y+=20;
   for(int i=0;i<8;i++)
   {
      Lbl(P+"rd"+(string)i,"", INL, y, COL_WHITE, 9, "Arial Bold");
      Lbl(P+"rh"+(string)i,"", INL+70, y, COL_WHITE, 9);
      Lbl(P+"rp"+(string)i,"", INL+150, y, COL_WHITE, 9);
      Lbl(P+"rl"+(string)i,"", INR, y, COL_WHITE, 9, "Arial", ANCHOR_RIGHT_UPPER);
      y+=20;
   }
   y+=6;
   Rect(P+"accbg", INL, y, P_W-2*PAD, 48, C'30,78,54', COL_GREEN, false);
   ObjectSetInteger(0,P+"accbg",OBJPROP_BACK,true);   // al fondo: no tapa el texto
   Lbl(P+"acct","GANANCIA ACUMULADA HOY", INL+(P_W-2*PAD)/2, y+7, C'205,222,210', 7, "Arial Bold", ANCHOR_UPPER);
   Lbl(P+"accv","+$0.00", INL+(P_W-2*PAD)/2, y+22, COL_GREEN, 14, "Arial Black", ANCHOR_UPPER); y+=56;
   mb=MathMax(mb,y);

   // HELP (?): tutorial + FAQ + estado actual + botones
   P=PFX+"help_"; y=pageY;
   Lbl(P+"tt","TUTORIAL", INL, y, COL_GOLD, 8, "Arial Bold"); y+=18;
   Lbl(P+"ttit","", INL, y, COL_BLUE, 10, "Arial Bold"); y+=20;
   for(int i=0;i<5;i++){ Lbl(P+"tl"+(string)i,"", INL, y, COL_GOLD, 8); y+=15; }
   Lbl(P+"tp","", INL, y, COL_GRAY, 7); y+=18;
   int thw=(P_W-2*PAD-8)/2;
   Btn(P+"tnext","SIGUIENTE", INL, y, thw, 22, 8);
   Btn(P+"tskip","SALTAR", INL+thw+8, y, thw, 22, 8); y+=30;
   Lbl(P+"fq","PREGUNTAS FRECUENTES", INL, y, COL_GOLD, 8, "Arial Bold");
   Btn(P+"fprev","<", INR-52, y-2, 24, 18, 9);
   Btn(P+"fnext",">", INR-24, y-2, 24, 18, 9); y+=18;
   Lbl(P+"fpq","", INL, y, COL_GOLD, 8, "Arial Bold"); y+=15;
   Lbl(P+"fpa","", INL, y, COL_WHITE, 8); y+=15;
   Lbl(P+"fpi","", INL, y, COL_GRAY, 7); y+=20;
   Lbl(P+"eal","ESTADO ACTUAL", INL, y, COL_GOLD, 8, "Arial Bold");
   Lbl(P+"eav","", INR, y, COL_GOLD, 9, "Arial Bold", ANCHOR_RIGHT_UPPER); y+=22;
   int hbw=(P_W-2*PAD-8)/2;
   Btn(PFX+"btnDIAG","DIAGNOSTICAR", INL, y, hbw, 26, 9);
   Btn(PFX+"btnGUIA","GUIA PARAMS", INL+hbw+8, y, hbw, 26, 9); y+=32;
   mb=MathMax(mb,y);

   // Anclar la caja "GANANCIA ACUMULADA HOY" al fondo del panel
   int accY=mb-48;
   ObjectSetInteger(0,PFX+"hist_accbg",OBJPROP_YDISTANCE, accY);
   ObjectSetInteger(0,PFX+"hist_acct", OBJPROP_YDISTANCE, accY+8);
   ObjectSetInteger(0,PFX+"hist_accv", OBJPROP_YDISTANCE, accY+24);

   ObjectSetInteger(0,PFX+"bg",OBJPROP_YSIZE,(mb+PAD)-Y);
   g_panelBottom=mb+PAD;
   g_lastChartW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   CreateMascota();
   ShowTab(g_activeTab);
   ChartRedraw();
}

// Mascota Toro (cambia de animo segun el estado)
void CreateMascota()
{
   Lbl(PFX+"masc_face","( o.o )", INL, g_panelBottom+8, COL_GOLD, 12, "Consolas");
   Lbl(PFX+"masc_cap","Toro - Descansando", INL, g_panelBottom+28, COL_GRAY, 8, "Arial Bold");
}

void SetPageVisible(string page,bool on)
{
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,page)==0)
         ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES, on?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
   }
}
// Boton flotante (independiente del panel) anclado a la derecha del chart.
// Siempre visible: minimiza (borra el panel) o restaura (lo reconstruye).
// Barra compacta cuando el panel esta minimizado (solo titulo + boton restaurar)
void CreateCollapsedBar()
{
   int X=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-P_W-InpPanelX;
   if(X<10) X=10;
   int Y=InpPanelY;
   Rect(PFX+"bg", X, Y, P_W, 30, COL_BG, COL_BORDER, false);
   Btn(PFX+"min","+", X+5, Y+5, 20, 18, 11);
   Lbl(PFX+"title","BAYESIAN STRATEGY", X+32, Y+8, COL_GOLD, 11, "Arial Black");
   g_lastChartW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
}
void HidePanel()
{
   ObjectsDeleteAll(0,PFX);       // borra panel + mascota
   g_panelHidden=true;
   CreateCollapsedBar();
   ChartRedraw();
}
void ShowPanel()
{
   ObjectsDeleteAll(0,PFX);
   g_panelHidden=false;
   CreatePanel();
   RefreshPanel();
   ChartRedraw();
}
void ShowTab(int tab)
{
   SetPageVisible(PFX+"cta_",  tab==0);
   SetPageVisible(PFX+"cfg_",  tab==1);
   SetPageVisible(PFX+"stat_", tab==2);
   SetPageVisible(PFX+"intel_",tab==3);
   SetPageVisible(PFX+"hist_", tab==4);
   SetPageVisible(PFX+"help_", tab==5);
   // Botones de accion: solo en CTA
   string ab[6]={"btnTRAIL","btnBE","btnSECURE","btnCLOSE","btnSHIELD","btnPAUSE"};
   for(int i=0;i<6;i++)
      ObjectSetInteger(0,PFX+ab[i],OBJPROP_TIMEFRAMES, (tab==0)?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
   // Diagnostico/guia: solo en ?
   ObjectSetInteger(0,PFX+"btnDIAG",OBJPROP_TIMEFRAMES, (tab==5)?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
   ObjectSetInteger(0,PFX+"btnGUIA",OBJPROP_TIMEFRAMES, (tab==5)?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
}

void Row(string page,string key,string label,int y)
{
   Lbl(page+"L_"+key, label, INL, y, COL_GRAY, 9);
   Lbl(page+"V_"+key, "-",   INR, y, COL_WHITE, 10, "Arial Bold", ANCHOR_RIGHT_UPPER);
}
// Fila con indicador V/X pulsable a la derecha
void ToggleRow(string page,string key,string label,int y)
{
   Lbl(page+"L_"+key, label, INL, y, COL_WHITE, 9);
   Btn(page+"T_"+key, "X", INR-28, y-2, 28, 18, 9);
}
void SetToggle(string page,string key,bool on)
{
   ObjectSetString (0,page+"T_"+key,OBJPROP_TEXT, on?"V":"X");
   ObjectSetInteger(0,page+"T_"+key,OBJPROP_BGCOLOR, on?C'20,60,35':C'44,26,26');
   ObjectSetInteger(0,page+"T_"+key,OBJPROP_COLOR,   on?COL_GREEN:COL_RED);
   ObjectSetInteger(0,page+"T_"+key,OBJPROP_BORDER_COLOR, on?COL_GREEN:C'90,50,50');
}
void SetV(string page,string key,string val,color c)
{
   ObjectSetString (0,page+"V_"+key,OBJPROP_TEXT,val);
   ObjectSetInteger(0,page+"V_"+key,OBJPROP_COLOR,c);
}
void BarRow(string page,string key,string label,int y)
{
   Lbl(page+"L_"+key, label, INL, y, COL_GRAY, 8);
   Rect(page+"BG_"+key, INL, y+12, P_W-2*PAD, 6, COL_TRACK, COL_TRACK, false);
   Rect(page+"FL_"+key, INL, y+12, 1, 6, COL_GOLD, COL_GOLD, false);
}
void SetBar(string page,string key,double frac,color c)
{
   int w=(int)MathMax(1,Clip(frac,0,1)*(P_W-2*PAD));
   ObjectSetInteger(0,page+"FL_"+key,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,page+"FL_"+key,OBJPROP_BGCOLOR,c);
   ObjectSetInteger(0,page+"FL_"+key,OBJPROP_COLOR,c);
}
void Sec(string name,string text,int y)
{
   Rect(name+"_ln",  INL, y-4, P_W-2*PAD, 1, C'60,55,30', C'60,55,30', false); // separador tenue
   Rect(name+"_dot", INL, y+2, 5, 5, COL_GOLD, COL_GOLD, false);                // vineta
   Lbl(name, text, INL+11, y, COL_GOLD, 8, "Arial Bold");
}

void Rect(string name,int x,int y,int w,int h,color bg,color border,bool raised)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w); ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE, raised?BORDER_RAISED:BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_COLOR,border); ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_BACK,false); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}
void Lbl(string name,string text,int x,int y,color c,int fs,string font="Arial",ENUM_ANCHOR_POINT anc=ANCHOR_LEFT_UPPER)
{
   if(text=="") text=" ";   // MT5 muestra "Label" si el texto queda vacio
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER); ObjectSetInteger(0,name,OBJPROP_ANCHOR,anc);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c); ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);
   ObjectSetString (0,name,OBJPROP_FONT,font); ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}
void Btn(string name,string text,int x,int y,int w,int h,int fs)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w); ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetString (0,name,OBJPROP_TEXT,text); ObjectSetInteger(0,name,OBJPROP_COLOR,COL_WHITE);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs); ObjectSetString(0,name,OBJPROP_FONT,"Arial Bold");
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,COL_CARD); ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'55,60,72');
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_CHART_CHANGE)
   {
      int w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
      if(w!=g_lastChartW)
      {
         ObjectsDeleteAll(0,PFX);
         if(g_panelHidden) CreateCollapsedBar();
         else { CreatePanel(); RefreshPanel(); }
         ChartRedraw();
      }
      return;
   }
   if(id!=CHARTEVENT_OBJECT_CLICK) return;
   if(sparam==PFX+"min")   // minimizar / restaurar
   {
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      if(g_panelHidden) ShowPanel(); else HidePanel();
      return;
   }
   if(AjustesClick(sparam)) return;
   if(ManualClick(sparam)) return;
   if(StringFind(sparam,PFX)!=0) return;
   if(sparam==PFX+"btnTRAIL")       g_trailOn=!g_trailOn;
   else if(sparam==PFX+"btnBE")     g_beOn=!g_beOn;
   else if(sparam==PFX+"btnSHIELD") g_shieldOn=!g_shieldOn;
   else if(sparam==PFX+"btnSECURE") CloseInProfit();
   else if(sparam==PFX+"btnCLOSE")  CloseAll();
   else if(sparam==PFX+"btnPAUSE")  g_paused=!g_paused;
   else if(sparam==PFX+"btnDIAG")   RunDiagnostico();
   else if(sparam==PFX+"btnGUIA")   { g_manualPag=0; g_manualOpen=true; CreateManual(); }
   else if(sparam==PFX+"cfg_pMAN")  { g_profile=MANUAL;      ApplyProfile(); }
   else if(sparam==PFX+"cfg_pCONS") { g_profile=CONSERVADOR; ApplyProfile(); }
   else if(sparam==PFX+"cfg_pBAL")  { g_profile=BALANCEADO;  ApplyProfile(); }
   else if(sparam==PFX+"cfg_pAGR")  { g_profile=AGRESIVO;    ApplyProfile(); }
   else if(sparam==PFX+"cfg_T_t24") g_use24=!g_use24;
   else if(sparam==PFX+"cfg_T_tny") g_useNY=!g_useNY;
   else if(sparam==PFX+"cfg_T_tas") g_useAsia=!g_useAsia;
   else if(sparam==PFX+"cfg_T_tlo") g_useLon=!g_useLon;
   else if(sparam==PFX+"cfg_T_tob") g_useObjetivo=!g_useObjetivo;
   else if(sparam==PFX+"cfg_T_tbe") g_beOn=!g_beOn;
   else if(sparam==PFX+"cfg_T_tsh") g_shieldOn=!g_shieldOn;
   else if(sparam==PFX+"cfg_T_tsp") g_useSpreadF=!g_useSpreadF;
   else if(sparam==PFX+"cfg_T_tmg") g_useMargin=!g_useMargin;
   else if(sparam==PFX+"cfg_T_tnw") g_useNews=!g_useNews;
   else if(sparam==PFX+"cfg_params") Alert("Pulsa F7 para abrir la ventana de parametros del EA.");
   else if(sparam==PFX+"help_tnext"){ if(g_tutStep<11) g_tutStep++; }
   else if(sparam==PFX+"help_tskip") g_tutStep=11;
   else if(sparam==PFX+"help_fprev"){ if(g_faqIdx>0) g_faqIdx--; }
   else if(sparam==PFX+"help_fnext") g_faqIdx++;
   else if(StringFind(sparam,PFX+"tab")==0)
   { g_activeTab=(int)StringToInteger(StringSubstr(sparam,StringLen(PFX)+3)); ShowTab(g_activeTab); }
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
   RefreshPanel(); ChartRedraw();
}

void RefreshPanel()
{
   if(!InpShowPanel) return;
   if(ObjectFind(0,PFX+"title")<0) return;

   ObjectSetString(0,PFX+"clock",OBJPROP_TEXT,TimeToString(g_useGMT?TimeGMT():TimeLocal(),TIME_MINUTES));
   bool inses=InSession(); string sname=SessionName();
   ObjectSetString (0,PFX+"sess",OBJPROP_TEXT, inses?("OPERANDO "+sname):"FUERA SES");
   ObjectSetInteger(0,PFX+"sess",OBJPROP_COLOR, inses?COL_GREEN:COL_GRAY);

   string cur=AccountInfoString(ACCOUNT_CURRENCY);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double gain=GananciaHoy();
   double spread=(SymbolInfoDouble(g_sym,SYMBOL_ASK)-SymbolInfoDouble(g_sym,SYMBOL_BID))/_Point;
   int w,l; CountWL(w,l);

   // CTA
   string C=PFX+"cta_";
   SetV(C,"eq",   StringFormat("%.2f %s",eq,cur), COL_GREEN);
   SetV(C,"bal",  StringFormat("%.2f %s",AccountInfoDouble(ACCOUNT_BALANCE),cur), COL_GREEN);
   SetV(C,"mfree",StringFormat("%.2f %s",AccountInfoDouble(ACCOUNT_MARGIN_FREE),cur), COL_GREEN);
   double mlvl=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   SetV(C,"mlvl", (mlvl>0?StringFormat("%.1f%%",mlvl):"-"), COL_BLUE);
   SetV(C,"caps", (string)CountPositions(), COL_WHITE);
   SetV(C,"gain", StringFormat("%s%.2f %s",(gain>=0?"+":""),gain,cur), gain>=0?COL_GREEN:COL_RED);
   SetV(C,"spread",StringFormat("%.1f pts",spread), COL_BLUE);
   double ddPct=DailyDDPct();
   SetV(C,"dd", StringFormat("%.1f%% / %.1f%%",ddPct,g_shieldMax), (ddPct>0?COL_RED:COL_BLUE));
   double frac=(g_shieldMax>0)?MathMin(1.0,ddPct/g_shieldMax):0.0;
   color barc=(frac<0.5)?COL_GREEN:(frac<0.8?COL_GOLD:COL_RED);
   ObjectSetInteger(0,C+"barfl",OBJPROP_XSIZE,(int)MathMax(1,frac*(P_W-2*PAD)));
   ObjectSetInteger(0,C+"barfl",OBJPROP_BGCOLOR,barc); ObjectSetInteger(0,C+"barfl",OBJPROP_COLOR,barc);
   SetV(C,"wl", StringFormat("%d / %d",w,l), COL_GREEN);
   SetV(C,"be", g_beOn?"Activo":"Inactivo", g_beOn?COL_GREEN:COL_GRAY);

   // CFG toggles
   string F=PFX+"cfg_";
   SetToggle(F,"t24",g_use24);
   SetToggle(F,"tny",g_useNY && !g_use24);
   SetToggle(F,"tas",g_useAsia && !g_use24);
   SetToggle(F,"tlo",g_useLon && !g_use24);
   SetToggle(F,"tob",g_useObjetivo);
   SetToggle(F,"tbe",g_beOn);
   SetToggle(F,"tsh",g_shieldOn);
   SetToggle(F,"tsp",g_useSpreadF);
   SetToggle(F,"tmg",g_useMargin);
   SetToggle(F,"tnw",g_useNews);
   string pf[4]={"pMAN","pCONS","pBAL","pAGR"};
   for(int i=0;i<4;i++)
   {
      bool act=((int)g_profile==i);
      ObjectSetInteger(0,F+pf[i],OBJPROP_BGCOLOR, act?COL_GOLD:COL_CARD);
      ObjectSetInteger(0,F+pf[i],OBJPROP_COLOR,   act?C'20,20,20':COL_GRAY);
   }

   // STAT
   // STAT (periodos, record, racha, misiones)
   RefreshStat(PFX+"stat_", w, l, gain);

   // INTEL
   string I=PFX+"intel_";
   ObjectSetString(0,I+"live",OBJPROP_TEXT, EstadoBot());
   int score=ScoreOperacion();
   SetV(I,"score", StringFormat("%d / 100",score), COL_BLUE);
   SetV(I,"estado", CalidadTxt(score), (score>=70?COL_GREEN:(score>=45?COL_GOLD:COL_GRAY)));
   SetBar(I,"scorebar", score/100.0, (score>=70?COL_GREEN:(score>=45?COL_GOLD:COL_RED)));
   double vratio=ATRRatio();
   string vnivel=VolNivel(vratio);
   SetV(I,"vol", vnivel+" ("+DoubleToString(vratio,2)+")", (vnivel=="MEDIA"?COL_GREEN:(vnivel=="EXTREMA"?COL_RED:COL_GOLD)));
   double conf=Confidence();
   SetV(I,"next", (score>=45?"Cercana":"Sin datos aun"), (score>=45?COL_GREEN:COL_GRAY));
   SetV(I,"nhoy", (string)(w+l), COL_WHITE);
   SetV(I,"conf", StringFormat("%.0f%%",conf), (conf>=60?COL_GREEN:(conf>=40?COL_GOLD:COL_GRAY)));
   SetV(I,"cstado", (conf>=60?"BUENA":(conf>=40?"REGULAR":"BAJA")), (conf>=60?COL_GREEN:(conf>=40?COL_GOLD:COL_GRAY)));
   SetBar(I,"confbar", conf/100.0, (conf>=60?COL_GREEN:(conf>=40?COL_GOLD:COL_RED)));

   // HIST (trades de hoy + acumulado)
   RefreshHist(PFX+"hist_");

   // HELP (?): tutorial + FAQ + estado actual
   string D=PFX+"help_";
   string ttit=""; string tl[]; TutorialTxt(g_tutStep,ttit,tl);
   ObjectSetString(0,D+"ttit",OBJPROP_TEXT,ttit);
   for(int i=0;i<5;i++) ObjectSetString(0,D+"tl"+(string)i,OBJPROP_TEXT,(i<ArraySize(tl)?tl[i]:" "));
   ObjectSetString(0,D+"tp",OBJPROP_TEXT,StringFormat("Paso %d/12",g_tutStep+1));
   int fn=FaqCount();
   if(g_faqIdx>=fn) g_faqIdx=fn-1;
   if(g_faqIdx<0) g_faqIdx=0;
   string fq="",fa=""; FaqTxt(g_faqIdx,fq,fa);
   ObjectSetString(0,D+"fpq",OBJPROP_TEXT,"P: "+fq);
   ObjectSetString(0,D+"fpa",OBJPROP_TEXT,"R: "+fa);
   ObjectSetString(0,D+"fpi",OBJPROP_TEXT,StringFormat("(%d/%d)",g_faqIdx+1,fn));
   string eest=""; color ecol=COL_GOLD; EstadoActual(eest,ecol);
   ObjectSetString (0,D+"eav",OBJPROP_TEXT,eest);
   ObjectSetInteger(0,D+"eav",OBJPROP_COLOR,ecol);

   // Botones
   BtnState("btnTRAIL",  g_trailOn?"TRAIL ON":"TRAIL OFF", g_trailOn, C'27,94,42');
   BtnState("btnBE",     g_beOn?"BE ON":"BE OFF",          g_beOn,    C'40,44,52');
   BtnState("btnSHIELD", g_shieldOn?"SHIELD ON":"SHIELD",  g_shieldOn && !g_shieldTripped, C'26,52,92');
   BtnState("btnPAUSE",  g_paused?"REANUDAR":"PAUSAR",     !g_paused, C'25,64,42');
   ObjectSetInteger(0,PFX+"btnSECURE",OBJPROP_BGCOLOR,COL_CARD);
   ObjectSetInteger(0,PFX+"btnCLOSE", OBJPROP_BGCOLOR,C'92,32,38');

   for(int i=0;i<6;i++)
   {
      bool act=(i==g_activeTab);
      ObjectSetInteger(0,PFX+"tab"+(string)i,OBJPROP_BGCOLOR, act?COL_GOLD:COL_CARD);
      ObjectSetInteger(0,PFX+"tab"+(string)i,OBJPROP_COLOR,   act?C'20,20,20':(i==3?COL_RED:COL_GRAY));
   }

   // Mascota Toro
   if(ObjectFind(0,PFX+"masc_cap")>=0)
   {
      string mood, face; color mc;
      if((g_shieldOn&&g_shieldTripped)||g_paused){ mood="Descansando"; face="( -.- ) z"; mc=COL_GRAY; }
      else if(gain>0){ mood="Euforico"; face="( ^o^ )!"; mc=COL_GREEN; }
      else if(!InSession()){ mood="En espera"; face="( o.o )?"; mc=COL_BLUE; }
      else { mood="Aliento"; face="( o.o )"; mc=COL_GOLD; }
      ObjectSetString (0,PFX+"masc_face",OBJPROP_TEXT,face);
      ObjectSetInteger(0,PFX+"masc_face",OBJPROP_COLOR,mc);
      ObjectSetString (0,PFX+"masc_cap",OBJPROP_TEXT,"Toro - "+mood);
   }
}
void BtnState(string name,string text,bool on,color onColor)
{
   ObjectSetString (0,PFX+name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,PFX+name,OBJPROP_BGCOLOR, on?onColor:COL_CARD);
   ObjectSetInteger(0,PFX+name,OBJPROP_COLOR, on?COL_WHITE:COL_GRAY);
}

//====================================================================
//  VENTANA DE VERIFICACION INICIAL (estilo dialogo de permisos)
//====================================================================
#define STPFX "bgset_"
void ChkRow(string key,string label,bool on,int x,int y)
{
   Rect(STPFX+key+"_b", x, y, 15, 15, on?C'225,240,230':C'245,225,225', on?C'40,150,90':C'190,80,80', false);
   Lbl(STPFX+key+"_m", on?"V":"X", x+3, y+1, on?C'30,130,70':C'180,60,60', 9, "Arial Bold");
   Lbl(STPFX+key+"_l", label, x+24, y+1, C'40,44,54', 9);
}
void CreateAjustes()
{
   int W=520, H=290;
   int X=(int)(ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-W)/2; if(X<10) X=10;
   int Y=80;
   Rect(STPFX+"bg", X, Y, W, H, C'238,240,244', C'120,124,132', false);
   // barra de titulo
   Rect(STPFX+"tb", X, Y, W, 26, C'224,227,234', C'224,227,234', false);
   Lbl(STPFX+"ttl","Expert - BayesianStrategy  ·  Verificacion inicial", X+12, Y+7, C'25,28,36', 9, "Arial Bold");

   bool live   =(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   bool autotr =(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool conn   =(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   bool simbolo=(StringFind(g_sym,"XAU")>=0 || StringFind(g_sym,"GOLD")>=0);
   bool demo   =((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO);

   int lx=X+24, rx=X+270, yy=Y+44;
   Lbl(STPFX+"h1","Permisos (Common)", lx, yy, C'70,74,84', 8, "Arial Bold");
   Lbl(STPFX+"h2","Seguridad",         rx, yy, C'70,74,84', 8, "Arial Bold"); yy+=22;

   ChkRow("c1","Trading en vivo permitido", live,   lx, yy);
   ChkRow("s1","Conexion al broker",        conn,   rx, yy); yy+=26;
   ChkRow("c2","AutoTrading activado",      autotr, lx, yy);
   ChkRow("s2","Simbolo XAUUSD / GOLD",     simbolo,rx, yy); yy+=26;
   ChkRow("c3","Alertas activas",           true,   lx, yy);
   ChkRow("s3",(demo?"Cuenta DEMO":"Cuenta REAL"), true, rx, yy); yy+=34;

   // resultado
   bool okAll=(live && conn && simbolo);
   Lbl(STPFX+"res", okAll?"TODO LISTO PARA OPERAR":"REVISA LOS PUNTOS EN ROJO ANTES DE OPERAR",
       lx, yy, okAll?C'30,130,70':C'190,80,80', 9, "Arial Bold"); yy+=10;

   if(!live)
      Lbl(STPFX+"hint","Consejo: activa 'AutoTrading' y 'Allow live trading' (pestana Common).",
          lx, yy+16, C'110,114,124', 8);

   // boton continuar
   int bw=120, bh=26, bx=X+W-bw-16, by=Y+H-bh-14;
   Btn(STPFX+"ok","CONTINUAR", bx, by, bw, bh, 9);
   ObjectSetInteger(0,STPFX+"ok",OBJPROP_BGCOLOR,C'40,110,220');
   ObjectSetInteger(0,STPFX+"ok",OBJPROP_COLOR,C'255,255,255');
   ObjectSetInteger(0,STPFX+"ok",OBJPROP_BORDER_COLOR,C'30,90,190');
   ChartRedraw();
}
void CloseAjustes(){ ObjectsDeleteAll(0,STPFX); ChartRedraw(); }
bool AjustesClick(string sparam)
{
   if(StringFind(sparam,STPFX)!=0) return false;
   if(sparam==STPFX+"ok")
   {
      CloseAjustes();
      if(Mostrar_Manual_Inicio && g_manualOpen) CreateManual();
   }
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
   return true;
}

//====================================================================
//  SPLASH DE ARRANQUE (pantalla inicial, estilo de la imagen)
//====================================================================
#define SPFX "bgspl_"
int SPX, SPY, SPW, SPH;

void CreateSplash()
{
   SPW=430; SPH=340;
   SPX=(int)(ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-SPW)/2; if(SPX<10) SPX=10;
   SPY=60;
   int x=SPX, y=SPY;

   Rect(SPFX+"bg", x, y, SPW, SPH, C'8,10,14', COL_BORDER, false);

   // Cabecera
   Lbl(SPFX+"t1","BAYESIAN STRATEGY", x+18, y+14, COL_GOLD, 15, "Arial Black");
   Rect(SPFX+"vip", x+SPW-58, y+14, 40, 18, COL_GOLD, COL_GOLD, false);
   Lbl(SPFX+"vipt","VIP", x+SPW-48, y+16, C'20,20,20', 9, "Arial Black");
   Lbl(SPFX+"t2","VIP EDITION PRO - "+g_sym+" M5", x+18, y+38, COL_GRAY, 8, "Arial Bold");

   // Barra licencia
   Rect(SPFX+"licbg", x+18, y+62, SPW-36, 26, C'18,20,26', COL_GOLD, false);
   Lbl(SPFX+"lic","Codigo aceptado  —  Licencia VIP vitalicia", x+30, y+68, COL_GOLD, 9, "Arial Bold");

   // Recuadro izq: par y capital
   Rect(SPFX+"boxL", x+18, y+100, (SPW-48)/2, 96, C'14,16,22', C'55,60,72', false);
   Lbl(SPFX+"lcap","PAR Y CAPITAL", x+28, y+106, COL_GRAY, 7, "Arial Bold");
   Lbl(SPFX+"lpar",g_sym+"  -  M5", x+28, y+122, COL_WHITE, 12, "Arial Black");
   Lbl(SPFX+"lmin","Min  $300 USD", x+28, y+146, COL_GRAY, 8);
   Lbl(SPFX+"lopt","Opt  $1,500 USD", x+28, y+162, COL_GRAY, 8);
   Lbl(SPFX+"lcent","Menos de $1,500 usa cuenta CENT", x+28, y+178, C'90,96,108', 7);

   // Recuadro der: sesiones activas (con TUS horarios reales)
   int rx=x+18+(SPW-48)/2+12;
   Rect(SPFX+"boxR", rx, y+100, (SPW-48)/2, 96, C'14,16,22', C'55,60,72', false);
   Lbl(SPFX+"lses","SESIONES ACTIVAS", rx+10, y+106, COL_GRAY, 7, "Arial Bold");
   Lbl(SPFX+"sNY","", rx+10, y+124, COL_GREEN, 9, "Arial Bold");
   Lbl(SPFX+"sAS","", rx+10, y+142, COL_GREEN, 9, "Arial Bold");
   Lbl(SPFX+"sLO","", rx+10, y+160, COL_GREEN, 9, "Arial Bold");
   Lbl(SPFX+"stz",(g_useGMT?"horario GMT":"hora del servidor"), rx+10, y+178, C'90,96,108', 7);

   // Tres cajas grandes
   int cy=y+206, cw=(SPW-36-2*10)/3, ch=58;
   Rect(SPFX+"c1", x+18,            cy, cw, ch, C'10,26,18', COL_GREEN, false);
   Lbl(SPFX+"c1v","M5", x+18+cw/2, cy+10, COL_GREEN, 16, "Arial Black", ANCHOR_UPPER);
   Lbl(SPFX+"c1t","TIMEFRAME", x+18+cw/2, cy+40, COL_GRAY, 7, "Arial Bold", ANCHOR_UPPER);
   Rect(SPFX+"c2", x+18+cw+10,      cy, cw, ch, C'10,20,32', COL_BLUE, false);
   Lbl(SPFX+"c2v","", x+18+cw+10+cw/2, cy+10, COL_BLUE, 16, "Arial Black", ANCHOR_UPPER);
   Lbl(SPFX+"c2t","SESIONES", x+18+cw+10+cw/2, cy+40, COL_GRAY, 7, "Arial Bold", ANCHOR_UPPER);
   Rect(SPFX+"c3", x+18+2*(cw+10),  cy, cw, ch, C'30,24,8', COL_GOLD, false);
   Lbl(SPFX+"c3v","", x+18+2*(cw+10)+cw/2, cy+10, COL_GOLD, 16, "Arial Black", ANCHOR_UPPER);
   Lbl(SPFX+"c3t","OPERATIVO", x+18+2*(cw+10)+cw/2, cy+40, COL_GRAY, 7, "Arial Bold", ANCHOR_UPPER);

   // Checks
   Lbl(SPFX+"ck","", x+18, cy+ch+14, COL_GREEN, 8, "Arial Bold");

   // Barra "Iniciando sistema..."
   Lbl(SPFX+"init","Iniciando sistema...", x+18, y+SPH-30, COL_GOLD, 9);
   Rect(SPFX+"pbbg", x+18, y+SPH-12, SPW-36, 5, COL_TRACK, COL_TRACK, false);
   Rect(SPFX+"pbfl", x+18, y+SPH-12, 4, 5, COL_GOLD, COL_GOLD, false);

   RenderSplash();
   ChartRedraw();
}
void RenderSplash()
{
   if(ObjectFind(0,SPFX+"bg")<0) return;
   // Sesiones reales del EA
   int nses=0; string ny="",as="",lo="";
   if(!Operar_24H)
   {
      ny=StringFormat("NY   %02d:00 - %02d:00",NY_Hora_Inicio,NY_Hora_Cierre);
      lo=StringFormat("Lon  %02d:00 - %02d:00",Londres_Hora_Inicio,Londres_Hora_Cierre);
      nses=2;
      if(g_useAsia){ as=StringFormat("Asia %02d:00 - %02d:00",Asia_Hora_Inicio,Asia_Hora_Cierre); nses=3; }
   }
   else { ny="Opera 24 horas"; nses=3; }
   ObjectSetString(0,SPFX+"sNY",OBJPROP_TEXT,ny);
   ObjectSetString(0,SPFX+"sAS",OBJPROP_TEXT,as);
   ObjectSetString(0,SPFX+"sLO",OBJPROP_TEXT,lo);
   ObjectSetString(0,SPFX+"c2v",OBJPROP_TEXT,(string)nses);
   ObjectSetString(0,SPFX+"c3v",OBJPROP_TEXT,(Operar_24H?"24/7":"24/5"));
   ObjectSetString(0,SPFX+"ck",OBJPROP_TEXT,"Licencia activa    Shield    Sesiones");
   // Barra de progreso animada
   int step=(g_splashTick%20)+1;
   int w=(int)((SPW-36)*step/20.0);
   ObjectSetInteger(0,SPFX+"pbfl",OBJPROP_XSIZE,(w<4?4:w));
}
void CloseSplash(){ ObjectsDeleteAll(0,SPFX); g_splashOn=false; ChartRedraw(); }

//====================================================================
//  MANUAL DE CONFIGURACION (overlay 16 paginas, estilo de la guia)
//====================================================================
#define MPFX "bgman_"
int MX, MY, MW, MH;   // geometria del overlay

// Contenido: titulo + hasta 12 lineas por pagina.
// Pagina 0 = portada (identica a la imagen). 1..15 = manual real de TU robot.
void ManualPagina(int p, string &titulo, string &lineas[])
{
   ArrayResize(lineas,0);
   switch(p)
   {
      case 0:
         titulo="Bayesian Strategy PRO";
         Push(lineas,"Manual tecnico de configuracion.");
         Push(lineas,"Robot de prediccion bayesiana para XAUUSD (Oro).");
         Push(lineas,"");
         Push(lineas,"QUE INCLUYE                  COMO NAVEGAR");
         Push(lineas,"La estrategia explicada      SIGUIENTE y ANTERIOR");
         Push(lineas,"Cada parametro de entrada    Navegacion libre entre paginas");
         Push(lineas,"Las 4 protecciones           Saltar en cualquier momento");
         Push(lineas,"Configuracion por cuenta     Al final: COMENZAR");
         Push(lineas,"");
         Push(lineas,"RECOMENDACION");
         Push(lineas,"Lee el manual completo antes de operar en cuenta real.");
         break;
      case 1:
         titulo="1. La estrategia";
         Push(lineas,"Motor bayesiano (naive Bayes en log-odds).");
         Push(lineas,"Combina 5 evidencias en una probabilidad P(subida):");
         Push(lineas," - RSI (sobreventa favorece compra)");
         Push(lineas," - CCI (extremos, sistema antiextremos)");
         Push(lineas," - Pendiente del RSI (momentum)");
         Push(lineas," - Cuerpo de vela / ATR (retorno)");
         Push(lineas," - Precio vs EMA lenta (tendencia)");
         Push(lineas,"Entra LONG si P>=Umbral; SELL si P<=1-Umbral.");
         Push(lineas,"Timeframe M5. Codigo abierto y auditable.");
         break;
      case 2:
         titulo="2. Parametros del motor";
         Push(lineas,"InpThreshold  = umbral de entrada (def 0.62).");
         Push(lineas,"InpPriorUp    = probabilidad a priori (0.50).");
         Push(lineas,"Pesos (calibrables con backtest):");
         Push(lineas," InpW_RSI 1.10  InpW_CCI 0.70  InpW_Slope 0.60");
         Push(lineas," InpW_Return 0.50  InpW_Trend 0.40");
         Push(lineas,"W_Trend >0 = seguidor; <0 = reversion a la media.");
         Push(lineas,"Sube el umbral para menos operaciones y mas calidad.");
         break;
      case 3:
         titulo="3. Filtros de entrada";
         Push(lineas,"InpUseRSIConfirm: confirma con RSI el lado.");
         Push(lineas," InpRSI_LongMax 55 / InpRSI_ShortMin 45.");
         Push(lineas,"InpUseAntiExtremos: no compra techos ni vende pisos.");
         Push(lineas," (RSI>75 & CCI>150 bloquea LONG; inverso el SELL).");
         Push(lineas,"InpUseVolGate: opera solo si ATR esta en banda.");
         Push(lineas," InpATRMinPts 80 / InpATRMaxPts 900.");
         break;
      case 4:
         titulo="4. Sesiones";
         Push(lineas,"Operar_24H: opera todo el dia (24h).");
         Push(lineas,"Operar_24H: opera todo el dia (ignora ventanas).");
         Push(lineas,"Ventanas (GMT si g_useGMT):");
         Push(lineas," Nueva York 12-21  Londres 7-16  Asia 0-8.");
         Push(lineas,"El header muestra OPERANDO <sesion> o FUERA SES.");
         Push(lineas,"Ojo con el DST: ajusta ventanas en verano.");
         break;
      case 5:
         titulo="5. Perfiles de riesgo";
         Push(lineas,"Cambialos en caliente en la pestana CFG:");
         Push(lineas," MAN  = manual (usas tus inputs).");
         Push(lineas," CONS = Shield 3%, riesgo 0.5%, 6 capas, BE 70%.");
         Push(lineas," BAL  = Shield 4%, riesgo 1.0%, 10 capas, BE 80%.");
         Push(lineas," AGR  = Shield 6%, riesgo 1.8%, 15 capas, BE 80%.");
         Push(lineas,"Nota: mas capas = mas riesgo. Empieza en CONS.");
         break;
      case 6:
         titulo="6. Proteccion: Shield";
         Push(lineas,"Stop-loss global diario.");
         Push(lineas,"Si el equity pierde Shield_Pct del balance");
         Push(lineas,"del dia, cierra TODO y pausa hasta el dia siguiente.");
         Push(lineas,"Boton SHIELD en el panel para armar/desarmar.");
         Push(lineas,"En fondeo: pon el Shield <= limite diario de tu firma.");
         break;
      case 7:
         titulo="7. Proteccion: Break-even";
         Push(lineas,"Mueve el SL a la entrada cuando ya casi ganaste.");
         Push(lineas,"InpBEMode = BE_POR_PCT_TP (por defecto).");
         Push(lineas," Activa a BE_Activacion del camino al TP.");
         Push(lineas," Recomendado 60-85%. (Perfiles: 70-80%).");
         Push(lineas,"Alternativa: BE_POR_ATR (a InpBE_ATR de ganancia).");
         Push(lineas,"InpBE_OffsetPts: colchon a favor sobre la entrada.");
         break;
      case 8:
         titulo="8. Proteccion: Trailing";
         Push(lineas,"Asegura un % de la ganancia flotante.");
         Push(lineas,"Trailing_Dist = 50% (recomendado).");
         Push(lineas,"Solo arranca tras ganar InpTrail_MinATR de ATR.");
         Push(lineas,"El SL sube (o baja en cortos) y no retrocede:");
         Push(lineas,"es como subir escalones que no puedes bajar.");
         break;
      case 9:
         titulo="9. Proteccion: Antiextremos";
         Push(lineas,"Evita entrar en zonas saturadas.");
         Push(lineas,"No compra si RSI>75 y CCI>150 (techo).");
         Push(lineas,"No vende si RSI<25 y CCI<-150 (piso).");
         Push(lineas,"Reduce las peores entradas de reversion.");
         break;
      case 10:
         titulo="10. Gestion del lote";
         Push(lineas,"InpRiskMode: RISK_PERCENT o RISK_FIXED_LOT.");
         Push(lineas,"Percent: arriesga InpRiskPercent del balance por");
         Push(lineas," trade, calculado desde el SL (ATR*InpSL_ATR).");
         Push(lineas,"TP = SL * InpTP_R (R multiple).");
         Push(lineas,"Los perfiles fuerzan modo porcentaje.");
         break;
      case 11:
         titulo="11. Capas (avanzado)";
         Push(lineas,"InpUseLayers: promedia en contra hasta N capas.");
         Push(lineas,"OFF por defecto. Es la parte de mayor riesgo.");
         Push(lineas," InpMaxLayers, InpLayerStepATR, InpLayerLotFactor.");
         Push(lineas,"El Shield sigue siendo el tope duro.");
         Push(lineas,"En fondeo: dejalas apagadas o al minimo.");
         break;
      case 12:
         titulo="12. El panel";
         Push(lineas,"6 pestanas: CTA (cuenta), CFG (config y perfil),");
         Push(lineas,"STAT (estadisticas), INTEL (que hace el bot),");
         Push(lineas,"HIST y ? (ayuda + DIAGNOSTICAR).");
         Push(lineas,"Botones: TRAIL, BE, SHIELD, ASEGURAR, CERRAR, PAUSA.");
         Push(lineas,"INTEL muestra la probabilidad en vivo y la confianza.");
         break;
      case 13:
         titulo="13. DIAGNOSTICAR";
         Push(lineas,"En la pestana de ayuda. Verifica 7 puntos:");
         Push(lineas,"AutoTrading, simbolo, conexion, equity, sesion,");
         Push(lineas,"spread y estado del Shield.");
         Push(lineas,"Imprime el reporte en el panel y en el log.");
         break;
      case 14:
         titulo="14. Recomendaciones";
         Push(lineas,"Empieza en DEMO con perfil Conservador.");
         Push(lineas,"Observa una semana antes de cuenta real.");
         Push(lineas,"Compila en MetaEditor y revisa el filling del broker.");
         Push(lineas,"Calibra con el estudio (In-Sample / Out-of-Sample).");
         Push(lineas,"Ningun panel garantiza rentabilidad: el edge lo");
         Push(lineas,"decide el backtest riguroso, no el marketing.");
         break;
      case 15:
         titulo="15. Aviso";
         Push(lineas,"Robot de codigo abierto para uso propio.");
         Push(lineas,"El trading en XAUUSD con apalancamiento puede");
         Push(lineas,"liquidar la cuenta. Esto NO es asesoria financiera.");
         Push(lineas,"Los objetivos diarios son metas, no rendimientos");
         Push(lineas,"garantizados. Opera bajo tu propio riesgo.");
         Push(lineas,"");
         Push(lineas,"Pulsa COMENZAR para cerrar el manual.");
         break;
      default: titulo=""; break;
   }
}
void Push(string &arr[], string v){ int n=ArraySize(arr); ArrayResize(arr,n+1); arr[n]=v; }

void CreateManual()
{
   MW=560; MH=440;
   MX=(int)(ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-MW)/2; if(MX<10) MX=10;
   MY=70;
   Rect(MPFX+"bg", MX, MY, MW, MH, C'10,12,16', COL_BORDER, false);
   Lbl(MPFX+"hdr","MANUAL DE CONFIGURACION", MX+24, MY+18, COL_GRAY, 8, "Arial Bold");
   Lbl(MPFX+"pag","01 / 16", MX+MW-24, MY+18, COL_GRAY, 9, "Consolas", ANCHOR_RIGHT_UPPER);
   Lbl(MPFX+"tit","", MX+24, MY+34, COL_GOLD, 14, "Arial Black");
   for(int i=0;i<12;i++)
      Lbl(MPFX+"l"+(string)i,"", MX+24, MY+74+i*20, COL_WHITE, 9, "Consolas");
   int bw=150,bh=28,by=MY+MH-40;
   Btn(MPFX+"prev","< ANTERIOR", MX+24, by, bw, bh, 9);
   Btn(MPFX+"skip","Saltar manual", MX+(MW-bw)/2, by, bw, bh, 8);
   Btn(MPFX+"next","SIGUIENTE >", MX+MW-24-bw, by, bw, bh, 9);
   ObjectSetInteger(0,MPFX+"next",OBJPROP_BGCOLOR,COL_GOLD);
   ObjectSetInteger(0,MPFX+"next",OBJPROP_COLOR,C'20,20,20');

   // --- Portada (pagina 0): estilo con cuadros ---
   Lbl(MPFX+"cv_s1","Version de prueba: 3 dias habiles gratis.", MX+24, MY+44, COL_WHITE, 10, "Arial");
   Lbl(MPFX+"cv_s2","Robot de prediccion bayesiana para XAUUSD (Oro).", MX+24, MY+62, COL_WHITE, 10, "Arial");
   Rect(MPFX+"cv_box1", MX+24, MY+92, 250, 122, C'14,16,22', COL_BORDER, false);
   Lbl(MPFX+"cv_b1h","QUE INCLUYE", MX+36, MY+100, COL_GOLD, 10, "Arial Bold");
   string q1a="Requisitos e instalacion", q1b="La estrategia explicada", q1c="Cada parametro de entrada", q1d="Las 4 protecciones", q1e="Solucion de problemas";
   Lbl(MPFX+"cv_i0",q1a, MX+36, MY+122, COL_WHITE, 9);
   Lbl(MPFX+"cv_i1",q1b, MX+36, MY+139, COL_WHITE, 9);
   Lbl(MPFX+"cv_i2",q1c, MX+36, MY+156, COL_WHITE, 9);
   Lbl(MPFX+"cv_i3",q1d, MX+36, MY+173, COL_WHITE, 9);
   Lbl(MPFX+"cv_i4",q1e, MX+36, MY+190, COL_WHITE, 9);
   Rect(MPFX+"cv_box2", MX+286, MY+92, 250, 122, C'14,16,22', COL_BORDER, false);
   Lbl(MPFX+"cv_b2h","COMO NAVEGAR", MX+298, MY+100, COL_GOLD, 10, "Arial Bold");
   Lbl(MPFX+"cv_j0","SIGUIENTE y ANTERIOR", MX+298, MY+122, COL_WHITE, 9);
   Lbl(MPFX+"cv_j1","Navegacion libre entre paginas", MX+298, MY+139, COL_WHITE, 9);
   Lbl(MPFX+"cv_j2","Saltar cuando quieras", MX+298, MY+156, COL_WHITE, 9);
   Lbl(MPFX+"cv_j3","Al final: COMENZAR", MX+298, MY+173, COL_WHITE, 9);
   Lbl(MPFX+"cv_rec","RECOMENDACION", MX+24, MY+228, COL_GREEN, 9, "Arial Bold");
   Lbl(MPFX+"cv_rect","Lee el manual completo antes de operar en cuenta real.", MX+24, MY+246, COL_WHITE, 9);

   RenderManual();
}
void ManualCoverVisible(bool on)
{
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,MPFX+"cv_")==0)
         ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES, on?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
   }
}
void RenderManual()
{
   if(ObjectFind(0,MPFX+"bg")<0) return;
   bool cover=(g_manualPag==0);
   ManualCoverVisible(cover);
   string titulo=""; string L[]; ManualPagina(g_manualPag,titulo,L);
   // titulo generico oculto en la portada
   ObjectSetInteger(0,MPFX+"tit",OBJPROP_TIMEFRAMES, cover?OBJ_NO_PERIODS:OBJ_ALL_PERIODS);
   ObjectSetString (0,MPFX+"tit",OBJPROP_TEXT,titulo);
   ObjectSetString (0,MPFX+"pag",OBJPROP_TEXT,StringFormat("%02d / %d",g_manualPag+1,MANUAL_PAGS));
   for(int i=0;i<12;i++)
   {
      ObjectSetInteger(0,MPFX+"l"+(string)i,OBJPROP_TIMEFRAMES, cover?OBJ_NO_PERIODS:OBJ_ALL_PERIODS);
      string t=(i<ArraySize(L)?L[i]:""); if(t=="") t=" ";   // evita el "Label" de MT5
      ObjectSetString(0,MPFX+"l"+(string)i,OBJPROP_TEXT, t);
   }
   ObjectSetString(0,MPFX+"prev",OBJPROP_TEXT, (g_manualPag==0?" ":"< ANTERIOR"));
   ObjectSetString(0,MPFX+"next",OBJPROP_TEXT, (g_manualPag>=MANUAL_PAGS-1?"COMENZAR":"SIGUIENTE >"));
   ChartRedraw();
}
void CloseManual(){ ObjectsDeleteAll(0,MPFX); g_manualOpen=false; ChartRedraw(); }
bool ManualClick(string sparam)
{
   if(StringFind(sparam,MPFX)!=0) return false;
   if(sparam==MPFX+"skip"){ CloseManual(); return true; }
   if(sparam==MPFX+"prev"){ if(g_manualPag>0){ g_manualPag--; RenderManual(); } }
   else if(sparam==MPFX+"next")
   {
      if(g_manualPag>=MANUAL_PAGS-1) CloseManual();
      else { g_manualPag++; RenderManual(); }
   }
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
   return true;
}

//====================================================================
//  CONTENIDO: HIST, TUTORIAL, FAQ, ESTADO ACTUAL
//====================================================================
int CollectTrades(string &dir[], string &hora[], double &pts[], double &pl[], int maxN)
{
   ArrayResize(dir,0); ArrayResize(hora,0); ArrayResize(pts,0); ArrayResize(pl,0);
   MqlDateTime t; TimeToStruct(TimeCurrent(),t); t.hour=0; t.min=0; t.sec=0;
   datetime dayStart=StructToTime(t);
   if(!HistorySelect(dayStart, TimeCurrent()+60)) return 0;
   double tv=SymbolInfoDouble(g_sym,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(g_sym,SYMBOL_TRADE_TICK_SIZE);
   double pvpl=(ts>0)? tv*(_Point/ts) : 0.0;   // valor por punto por lote
   int total=HistoryDealsTotal(), count=0;
   for(int i=total-1;i>=0 && count<maxN;i--)
   {
      ulong tk=HistoryDealGetTicket(i);
      if(HistoryDealGetString(tk,DEAL_SYMBOL)!=g_sym) continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=InpMagic) continue;
      if(HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      long dt=HistoryDealGetInteger(tk,DEAL_TYPE);
      string d=(dt==DEAL_TYPE_SELL)?"BUY":"SELL";  // cierre SELL => el trade fue BUY
      datetime dtime=(datetime)HistoryDealGetInteger(tk,DEAL_TIME);
      double profit=HistoryDealGetDouble(tk,DEAL_PROFIT);
      double vol=HistoryDealGetDouble(tk,DEAL_VOLUME);
      double p=(pvpl>0 && vol>0)? profit/(pvpl*vol) : 0.0;
      double pnl=profit+HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_COMMISSION);
      int n=ArraySize(dir);
      ArrayResize(dir,n+1); ArrayResize(hora,n+1); ArrayResize(pts,n+1); ArrayResize(pl,n+1);
      dir[n]=d; hora[n]=TimeToString(dtime,TIME_MINUTES); pts[n]=p; pl[n]=pnl;
      count++;
   }
   return count;
}
//====================================================================
//  ESTADISTICAS: PERIODOS, RECORD, RACHA, MISIONES
//====================================================================
double RealizedSince(datetime start)
{
   double r=0;
   if(!HistorySelect(start, TimeCurrent()+60)) return 0;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
   {
      ulong tk=HistoryDealGetTicket(i);
      if(HistoryDealGetString(tk,DEAL_SYMBOL)!=g_sym) continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=InpMagic) continue;
      if(HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      r+=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_COMMISSION);
   }
   return r;
}
datetime MonthStart()
{
   MqlDateTime s; TimeToStruct(TimeCurrent(),s);
   s.day=1; s.hour=0; s.min=0; s.sec=0;
   return StructToTime(s);
}
datetime WeekStart()
{
   datetime now=TimeCurrent();
   MqlDateTime s; TimeToStruct(now,s);
   int dow=s.day_of_week; if(dow==0) dow=7;   // domingo=0 -> 7
   datetime d0=now-(dow-1)*86400;
   MqlDateTime s2; TimeToStruct(d0,s2); s2.hour=0; s2.min=0; s2.sec=0;
   return StructToTime(s2);
}
void ComputeDaysStats()
{
   g_stBestDay=0; g_stBestDate=""; g_stPosDays=0; g_stMaxStreak=0;
   if(!HistorySelect(0, TimeCurrent()+60)) return;
   int total=HistoryDealsTotal();
   int days[]; double sums[]; datetime dts[];
   for(int i=0;i<total;i++)
   {
      ulong tk=HistoryDealGetTicket(i);
      if(HistoryDealGetString(tk,DEAL_SYMBOL)!=g_sym) continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=InpMagic) continue;
      if(HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      datetime dt=(datetime)HistoryDealGetInteger(tk,DEAL_TIME);
      MqlDateTime s; TimeToStruct(dt,s); s.hour=0; s.min=0; s.sec=0;
      datetime dayStart=StructToTime(s);
      int ymd=s.year*10000+s.mon*100+s.day;
      double p=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_COMMISSION);
      int idx=-1, nd=ArraySize(days);
      for(int j=0;j<nd;j++) if(days[j]==ymd){ idx=j; break; }
      if(idx<0){ idx=nd; ArrayResize(days,nd+1); ArrayResize(sums,nd+1); ArrayResize(dts,nd+1); days[idx]=ymd; sums[idx]=0; dts[idx]=dayStart; }
      sums[idx]+=p;
   }
   int n=ArraySize(days);
   if(n==0) return;
   int bi=0; for(int i=1;i<n;i++) if(sums[i]>sums[bi]) bi=i;
   g_stBestDay=sums[bi];
   g_stBestDate=TimeToString(dts[bi],TIME_DATE);
   // ordenar por fecha ascendente
   for(int a=0;a<n-1;a++) for(int b=0;b<n-1-a;b++)
      if(days[b]>days[b+1]){ int td=days[b]; days[b]=days[b+1]; days[b+1]=td;
                             double ts=sums[b]; sums[b]=sums[b+1]; sums[b+1]=ts; }
   int cur=0,mx=0;
   for(int i=0;i<n;i++){ if(sums[i]>0){ cur++; if(cur>mx) mx=cur; } else cur=0; }
   g_stPosDays=cur; g_stMaxStreak=mx;
}
void ComputeStatsCached()
{
   if(g_stLastCalc>0 && TimeCurrent()-g_stLastCalc<30) return;   // recalcular cada 30s
   g_stLastCalc=TimeCurrent();
   double fl=FloatingPnL();
   g_stWeek =RealizedSince(WeekStart())+fl;
   g_stMonth=RealizedSince(MonthStart())+fl;
   ComputeDaysStats();
}
string Money(double v){ return StringFormat("%s$%.2f",(v>=0?"+":"-"),MathAbs(v)); }
void SetMision(string S,string key,bool done,string txt)
{
   ObjectSetString (0,S+key,OBJPROP_TEXT,(done?"V ":"- ")+txt);
   ObjectSetInteger(0,S+key,OBJPROP_COLOR, done?COL_GREEN:C'150,155,165');
}
void RefreshStat(string S,int w,int l,double gain)
{
   if(ObjectFind(0,S+"V_hoy")<0) return;
   ComputeStatsCached();
   // Estadisticas (lo que ya estaba)
   int tot=w+l; double wr=(tot>0)?100.0*w/tot:0.0;
   SetV(S,"wl", StringFormat("%d / %d",w,l), COL_GREEN);
   SetV(S,"wr", StringFormat("%.0f%%",wr), (wr>=50?COL_GREEN:COL_GRAY));
   SetV(S,"gain", StringFormat("%s%.2f",(gain>=0?"+":""),gain), gain>=0?COL_GREEN:COL_RED);
   SetV(S,"npos", (string)CountPositions(), COL_WHITE);
   SetV(S,"prob", StringFormat("%.1f%%",g_lastP*100.0), COL_BLUE);
   SetV(S,"osc", StringFormat("%.0f / %.0f",g_lastRSI,g_lastCCI), COL_WHITE);
   // Periodos
   SetV(S,"sem", Money(g_stWeek),    g_stWeek>=0?COL_GREEN:COL_RED);
   SetV(S,"mes", Money(g_stMonth),   g_stMonth>=0?COL_GREEN:COL_RED);
   SetV(S,"best", Money(g_stBestDay), COL_GOLD);
   SetV(S,"bestd", (g_stBestDate==""?"---":g_stBestDate), COL_BLUE);
   SetV(S,"pos", StringFormat("%d dias",g_stPosDays), COL_WHITE);
   SetV(S,"max", StringFormat("%d dias",g_stMaxStreak), COL_GOLD);
   // Misiones de hoy
   bool m0=(gain>=50.0), m1=(!g_shieldTripped), m2=(w>=5);
   int done=(m0?1:0)+(m1?1:0)+(m2?1:0);
   ObjectSetString (0,S+"mcount",OBJPROP_TEXT,StringFormat("%d / 3",done));
   ObjectSetInteger(0,S+"mcount",OBJPROP_COLOR, done==3?COL_GREEN:(done>0?COL_GOLD:COL_RED));
   SetMision(S,"m0",m0,"Cerrar +$50");
   SetMision(S,"m1",m1,"Sin Shield activado");
   SetMision(S,"m2",m2,"5 trades ganadores");
}

void RefreshHist(string H)
{
   if(ObjectFind(0,H+"accv")<0) return;
   string dir[],hora[]; double pts[],pl[];
   int n=CollectTrades(dir,hora,pts,pl,8);
   for(int i=0;i<8;i++)
   {
      if(i<n)
      {
         ObjectSetString (0,H+"rd"+(string)i,OBJPROP_TEXT,dir[i]);
         ObjectSetInteger(0,H+"rd"+(string)i,OBJPROP_COLOR,(dir[i]=="BUY")?COL_GREEN:COL_RED);
         ObjectSetString (0,H+"rh"+(string)i,OBJPROP_TEXT,hora[i]);
         ObjectSetString (0,H+"rp"+(string)i,OBJPROP_TEXT,StringFormat("%s%.0f",(pts[i]>=0?"+":""),pts[i]));
         ObjectSetString (0,H+"rl"+(string)i,OBJPROP_TEXT,StringFormat("%s$%.2f",(pl[i]>=0?"+":"-"),MathAbs(pl[i])));
         ObjectSetInteger(0,H+"rl"+(string)i,OBJPROP_COLOR,(pl[i]>=0?COL_GREEN:COL_RED));
      }
      else
      {
         ObjectSetString(0,H+"rd"+(string)i,OBJPROP_TEXT," ");
         ObjectSetString(0,H+"rh"+(string)i,OBJPROP_TEXT," ");
         ObjectSetString(0,H+"rp"+(string)i,OBJPROP_TEXT," ");
         ObjectSetString(0,H+"rl"+(string)i,OBJPROP_TEXT," ");
      }
   }
   double acc=GananciaHoy();
   ObjectSetString (0,H+"accv",OBJPROP_TEXT,StringFormat("%s$%.2f",(acc>=0?"+":"-"),MathAbs(acc)));
   ObjectSetInteger(0,H+"accv",OBJPROP_COLOR,COL_GREEN);
   ObjectSetInteger(0,H+"accbg",OBJPROP_COLOR,COL_GREEN);
}

void TutorialTxt(int step,string &titulo,string &L[])
{
   ArrayResize(L,0);
   switch(step)
   {
      case 0: titulo="1. Bienvenido";
         Push(L,"Soy tu robot Bayesian Strategy.");
         Push(L,"Opero XAUUSD en M5 con probabilidad");
         Push(L,"bayesiana y proteccion Shield.");
         Push(L,"Sigueme paso a paso."); break;
      case 1: titulo="2. El motor";
         Push(L,"Calculo P(subida) con RSI y CCI,");
         Push(L,"momentum y tendencia. Entro cuando");
         Push(L,"la probabilidad pasa el umbral."); break;
      case 2: titulo="3. Sesiones";
         Push(L,"Opero NY, Londres y Asia, o 24h.");
         Push(L,"Cambialo en la pestana CFG."); break;
      case 3: titulo="4. Perfiles";
         Push(L,"MAN/CONS/BAL/AGR ajustan riesgo,");
         Push(L,"capas, objetivo y Shield de un clic."); break;
      case 4: titulo="5. Shield";
         Push(L,"Stop-loss global diario. Si el dia");
         Push(L,"pierde X%, cierro todo y descanso."); break;
      case 5: titulo="6. Break-even";
         Push(L,"Muevo el SL a la entrada al llegar");
         Push(L,"a un % del camino al TP."); break;
      case 6: titulo="7. Trailing";
         Push(L,"Aseguro un % de la ganancia y");
         Push(L,"subo el SL sin retroceder."); break;
      case 7: titulo="8. Filtros Pro";
         Push(L,"Spread, margen y noticias: evito");
         Push(L,"operar en malas condiciones."); break;
      case 8: titulo="9. INTEL";
         Push(L,"Te digo en vivo que estoy haciendo,");
         Push(L,"el score y la confianza del trade."); break;
      case 9: titulo="10. STAT / HIST";
         Push(L,"Estadisticas y las operaciones del");
         Push(L,"dia con su P&L acumulado."); break;
      case 10: titulo="11. DIAGNOSTICAR";
         Push(L,"Reviso 7 puntos antes de operar");
         Push(L,"y te digo que falta."); break;
      case 11: titulo="12. Listo";
         Push(L,"Empieza en DEMO con perfil CONS.");
         Push(L,"Calibra antes de cuenta real.");
         Push(L,"NO garantizo rentabilidad."); break;
      default: titulo=""; break;
   }
}
int FaqCount(){ return 8; }
void FaqTxt(int i,string &q,string &a)
{
   switch(i)
   {
      case 0: q="Que es Shield?";     a="Stop Loss global por %."; break;
      case 1: q="Operar 24h?";        a="Activa 24 HORAS en CFG."; break;
      case 2: q="Cual perfil uso?";   a="Empieza en Conservador."; break;
      case 3: q="Por que no opera?";  a="Fuera de sesion o spread alto."; break;
      case 4: q="Que es una capa?";   a="Promediar en contra. Riesgo alto."; break;
      case 5: q="Sirve en fondeo?";   a="Si, con perfil conservador."; break;
      case 6: q="Que timeframe uso?"; a="M5 en XAUUSD."; break;
      case 7: q="Garantiza ganar?";   a="No. Depende del backtest."; break;
      default: q=""; a=""; break;
   }
}
void EstadoActual(string &txt,color &col)
{
   bool autotr=(bool)MQLInfoInteger(MQL_TRADE_ALLOWED) && (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool simbolo=(StringFind(g_sym,"XAU")>=0 || StringFind(g_sym,"GOLD")>=0);
   bool conn=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   double spr=(SymbolInfoDouble(g_sym,SYMBOL_ASK)-SymbolInfoDouble(g_sym,SYMBOL_BID))/_Point;
   bool ses=InSession();
   if(!autotr || !conn || !simbolo){ txt="REVISAR";    col=COL_RED;  return; }
   if(!ses || spr>Spread_Max) { txt="CASI LISTO"; col=COL_GOLD; return; }
   txt="TODO LISTO"; col=COL_GREEN;
}

//====================================================================
//  ONTESTER — "Custom max"
//====================================================================
double OnTester()
{
   double pf     = TesterStatistics(STAT_PROFIT_FACTOR);
   double trades = TesterStatistics(STAT_TRADES);
   double ddpct  = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double net    = TesterStatistics(STAT_PROFIT);
   double sharpe = TesterStatistics(STAT_SHARPE_RATIO);
   if(trades<40) return 0.0;
   if(net<=0)    return 0.0;
   if(pf<1.15)   return 0.0;
   if(ddpct>25.0)return 0.0;
   double score = pf*MathSqrt(trades)/(1.0+ddpct/10.0);
   score *= (1.0+MathMax(sharpe,0.0)*0.1);
   return score;
}
//+------------------------------------------------------------------+
