//+------------------------------------------------------------------+
//| BayesianGold_XAU_Panel_core.mq5                                   |
//| EXTRACTO fiel (trading-logic-only) de BayesianGold_XAU_Panel.mq5  |
//| v1.78. Se omitio ~1180 lineas de UI (panel/splash/manual/FAQ)     |
//| porque estan gateadas por MQLInfoInteger(MQL_TESTER) o solo se    |
//| disparan por clics de boton (OnChartEvent) -> nunca se ejecutan   |
//| en un backtest no-visual y no afectan ninguna decision de trading |
//| ni el resultado de OnTester(). Todo lo demas es copia verbatim.   |
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
   g_use24=Operar_24H; g_useNY=Sesion_NuevaYork; g_useLon=Sesion_Londres; g_useAsia=Sesion_Asia;
   g_useGMT=!Usar_Hora_Local;
   g_useObjetivo=Usar_Objetivo; g_useSpreadF=Usar_Spread_Max; g_useMargin=Usar_Margen; g_useNews=Usar_Noticias;
   ApplyProfile();
   ResetDay();
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
}

//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDayAndShield();
   ManagePositions();

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
double Sigmoid(double x){ return 1.0/(1.0+MathExp(-x)); }
double Logit(double p){ p=Clip(p,1e-6,1.0-1e-6); return MathLog(p/(1.0-p)); }
double Clip(double v,double lo,double hi){ return (v<lo?lo:(v>hi?hi:v)); }

//====================================================================
//  INDICADORES
//====================================================================
double GetRSI(int shift){ double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(hRSI,0,shift+1,1,b)<1) return 50.0; return b[0]; }
double GetCCI(int shift){ double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(hCCI,0,shift+1,1,b)<1) return 0.0; return b[0]; }
double GetATR(){ double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(hATR,0,1,1,b)<1) return 0.0; return b[0]; }
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
double EmaBuf(int h){ double b[]; ArraySetAsSeries(b,true);
   if(h==INVALID_HANDLE || CopyBuffer(h,0,1,1,b)<1) return 0.0; return b[0]; }
bool EMAAllows(bool isLong)
{
   if(!Usar_EMA_Filter) return true;
   double f=EmaBuf(hEMAf), s=EmaBuf(hEMAs);
   if(f<=0 || s<=0) return true;                       // sin datos: no bloquear
   double price=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double sepPct=(price>0)? (f-s)/price*100.0 : 0.0;   // con signo: + alcista, - bajista
   if(MathAbs(sepPct) < EMA_Sep_Extrema) return true;
   return isLong ? (sepPct>0) : (sepPct<0);
}

//====================================================================
//  SESIONES
//====================================================================
bool g_use24, g_useNY, g_useAsia, g_useLon, g_useGMT;
bool g_useObjetivo, g_useSpreadF, g_useMargin, g_useNews;
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
void OpenTrade(ENUM_ORDER_TYPE type)
{
   double atr=GetATR(); if(atr<=0) return;
   double slDist=atr*InpSL_ATR;
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
   if(type==ORDER_TYPE_BUY) trade.Buy(lot,g_sym,0.0,sl,tp,"Bayes base");
   else                     trade.Sell(lot,g_sym,0.0,sl,tp,"Bayes base");
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
      double buffer =minStop+20*_Point;
      double step   =10*_Point;

      if(type==POSITION_TYPE_BUY)
      {
         double price=bid, gain=price-open;
         if(g_beOn)
         {
            bool trig=false;
            if(InpBEMode==BE_POR_PCT_TP && tp>open)
               trig = (price >= open + (tp-open)*g_bePct/100.0);
            else
               trig = (gain >= InpBE_ATR*atr);
            if(trig){ double be=open+InpBE_OffsetPts*_Point; if(be>newSL) newSL=be; }
         }
         bool trailOn=false;
         if(tp>open) trailOn = (price >= open + (tp-open)*Trailing_Activar/100.0);
         else        trailOn = (gain >= InpTrail_MinATR*atr);
         if(g_trailOn && trailOn)
         {
            double tr=open + gain*Trailing_Dist/100.0;
            if(tr>newSL) newSL=tr;
         }
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
//  SHIELD / OBJETIVO / FRENO
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
int g_dayStampCk; // (placeholder eliminado; usar g_dayStamp declarado arriba)
void UpdateDayAndShield()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   if(t.day_of_year!=g_dayStamp) ResetDay();
   if(g_shieldOn && !g_shieldTripped && DailyDDPct()>=g_shieldMax)
   {
      g_shieldTripped=true;
      if(InpShieldCloseAll) CloseAll();
   }
   if(g_useObjetivo && !g_objTripped && ObjetivoAlcanzado())
   {
      g_objTripped=true;
      CloseAll();
   }
}
bool ObjetivoAlcanzado()
{
   double meta=(g_profile==MANUAL)? Objetivo_Diario : g_objetivoPct;
   return (meta>0 && DailyGainPct()>=meta);
}

//====================================================================
//  UTILIDADES DE POSICION Y CUENTA
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
double GananciaHoy(){ return RealizedToday()+FloatingPnL(); }
double DayStartBalance()
{
   double b=AccountInfoDouble(ACCOUNT_BALANCE)-RealizedToday();
   return (b>0? b : AccountInfoDouble(ACCOUNT_BALANCE));
}
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
   return (now>=ini || now<fin);
}
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
//  ONTESTER — "Custom max" (criterio de aceptacion/optimizacion)
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
