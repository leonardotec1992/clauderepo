//+------------------------------------------------------------------+
//|                                        MultiEstrategia_XAU.mq5    |
//|  Banco de pruebas: 4 estrategias de tendencia, INDEPENDIENTES.    |
//|  Cada una tiene su Magic propio, opera sin bloquear a las otras,  |
//|  y queda ETIQUETADA en el CSV para analizarlas por separado.      |
//|    1) TENDENCIA  - ruptura de canal Donchian + filtro EMA         |
//|    2) ORB        - ruptura del rango de apertura                  |
//|    3) MOMENTUM   - ADX fuerte + direccion DI                      |
//|    4) PULLBACK   - retroceso a la EMA en tendencia                |
//|  Codigo abierto. NO promete rentabilidad. Uso bajo tu riesgo.     |
//+------------------------------------------------------------------+
#property copyright "Plantilla abierta"
#property version   "1.02"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================== INPUTS ======================================
input string _gen = "===== GENERAL =====";
input double Lote            = 0.01;    // Lote por operacion (fijo)
input double SL_ATR          = 2.0;     // Stop Loss = ATR x esto
input double TP_R            = 2.0;     // Take Profit = SL x esto
input int    ATR_Periodo     = 14;
input int    Desviacion      = 30;      // Slippage en puntos
input long   Magic_Base      = 55000;   // Magic base (cada estrategia usa base+1..+4)
input bool   Guardar_CSV     = true;
input bool   Alertas_Movil   = false;

input string _t1 = "===== 1) TENDENCIA (Donchian) =====";
input bool   Usar_Trend      = true;
input int    Trend_Donchian  = 20;      // Rompe el maximo/minimo de estas velas
input int    Trend_EMA_Fast  = 50;
input int    Trend_EMA_Slow  = 200;

input string _t2 = "===== 2) ORB (rango de apertura) =====";
input bool   Usar_ORB        = true;
input int    ORB_Hora_Inicio = 8;       // Hora (local) de apertura de sesion
input int    ORB_Rango_Min   = 60;      // Duracion del rango en minutos
input double ORB_Buffer_Pts  = 0;       // Puntos extra para confirmar ruptura (0 = al toque)
input int    ORB_Max_Horas   = 24;      // Solo opera la ruptura dentro de estas horas tras el rango

input string _t3 = "===== 3) MOMENTUM (ADX + DI) =====";
input bool   Usar_Momentum   = true;
input int    Mom_ADX_Periodo = 14;
input double Mom_ADX_Min     = 25.0;    // Solo entra si el ADX supera esto

input string _t4 = "===== 4) PULLBACK a EMA =====";
input bool   Usar_Pullback   = true;
input int    PB_EMA_Fast     = 50;
input int    PB_EMA_Slow     = 200;

input string _hr = "===== HORARIO =====";
input bool   Usar_Hora_Local = true;    // Referencia de hora: PC (true) o GMT (false)
input bool   Operar_24H      = true;
input int    Hora_Inicio     = 0;
input int    Hora_Fin        = 23;

//====================== ESTADO ======================================
int    hATR=INVALID_HANDLE, hTrendF=INVALID_HANDLE, hTrendS=INVALID_HANDLE;
int    hADX=INVALID_HANDLE, hPBf=INVALID_HANDLE, hPBs=INVALID_HANDLE;
datetime g_lastBar=0;
// ORB
int    g_orbDay=-1; double g_orbHi=-1.0, g_orbLo=DBL_MAX; bool g_orbTraded=false;
uint   g_lastPanel=0;

long MagTrend(){ return Magic_Base+1; }
long MagORB(){   return Magic_Base+2; }
long MagMom(){   return Magic_Base+3; }
long MagPB(){    return Magic_Base+4; }
string StrategyName(long m)
{
   if(m==MagTrend()) return "TREND";
   if(m==MagORB())   return "ORB";
   if(m==MagMom())   return "MOMENTUM";
   if(m==MagPB())    return "PULLBACK";
   return "?";
}

//====================== UTILIDADES ==================================
datetime RefTime(){ return (Usar_Hora_Local? TimeLocal() : TimeGMT()); }
bool NewBar()
{
   datetime t=iTime(_Symbol,PERIOD_CURRENT,0);
   if(t!=g_lastBar){ g_lastBar=t; return true; }
   return false;
}
double BufV(int handle,int buf,int shift)
{
   double b[]; ArraySetAsSeries(b,true);
   if(handle==INVALID_HANDLE || CopyBuffer(handle,buf,shift,1,b)<1) return 0.0;
   return b[0];
}
double ATRv(int sh){ return BufV(hATR,0,sh); }
double HighestHigh(int count,int startShift)
{
   double m=-DBL_MAX;
   for(int i=0;i<count;i++){ double h=iHigh(_Symbol,PERIOD_CURRENT,startShift+i); if(h>m) m=h; }
   return m;
}
double LowestLow(int count,int startShift)
{
   double m=DBL_MAX;
   for(int i=0;i<count;i++){ double l=iLow(_Symbol,PERIOD_CURRENT,startShift+i); if(l<m) m=l; }
   return m;
}
bool EnHorario()
{
   if(Operar_24H) return true;
   MqlDateTime t; TimeToStruct(RefTime(),t);
   if(Hora_Inicio<=Hora_Fin) return (t.hour>=Hora_Inicio && t.hour<=Hora_Fin);
   return (t.hour>=Hora_Inicio || t.hour<=Hora_Fin);
}
bool HasPos(long magic)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==magic)
         return true;
   }
   return false;
}

//====================== APERTURA + REGISTRO =========================
void LogOpen(string estrategia,ENUM_ORDER_TYPE type,double price,double lot,
             double sl,double tp,double atr,double slDist,long posid)
{
   string dir=(type==ORDER_TYPE_BUY)?"BUY":"SELL";
   double slPts=slDist/_Point, tpPts=MathAbs(tp-price)/_Point;
   double spr=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;
   PrintFormat("[OPEN] %s %s %s | entrada=%.2f lote=%.2f SL=%.2f (%.0f pts) TP=%.2f (%.0f pts) ATR=%.0f",
      estrategia, dir, _Symbol, price, lot, sl, slPts, tp, tpPts, atr/_Point);
   if(Alertas_Movil)
      SendNotification(StringFormat("%s %s %s lote %.2f", estrategia, dir, _Symbol, lot));
   if(!Guardar_CSV) return;
   string fn="MultiEstrategia_"+_Symbol+"_trades.csv";
   int h=FileOpen(fn, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"fecha","hora","estrategia","magic","pos_id","dir","entrada","lote",
                  "sl","sl_pts","tp","tp_pts","atr_pts","spread_pts");
   FileSeek(h,0,SEEK_END);
   FileWrite(h, TimeToString(TimeCurrent(),TIME_DATE), TimeToString(TimeCurrent(),TIME_SECONDS),
      estrategia, (string)PositionMagicFromName(estrategia), (string)posid, dir,
      DoubleToString(price,2), DoubleToString(lot,2),
      DoubleToString(sl,2), DoubleToString(slPts,0),
      DoubleToString(tp,2), DoubleToString(tpPts,0),
      DoubleToString(atr/_Point,0), DoubleToString(spr,1));
   FileClose(h);
}
long PositionMagicFromName(string name)
{
   if(name=="TREND") return MagTrend();
   if(name=="ORB") return MagORB();
   if(name=="MOMENTUM") return MagMom();
   if(name=="PULLBACK") return MagPB();
   return Magic_Base;
}
void OpenTrade(long magic,ENUM_ORDER_TYPE type,string estrategia)
{
   double atr=ATRv(1); if(atr<=0) return;
   double slDist=atr*SL_ATR, tpDist=slDist*TP_R;
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double price=(type==ORDER_TYPE_BUY)?ask:bid;
   double sl=(type==ORDER_TYPE_BUY)? price-slDist : price+slDist;
   double tp=(type==ORDER_TYPE_BUY)? price+tpDist : price-tpDist;
   sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(Desviacion);
   bool ok=(type==ORDER_TYPE_BUY)? trade.Buy(Lote,_Symbol,price,sl,tp,estrategia)
                                  : trade.Sell(Lote,_Symbol,price,sl,tp,estrategia);
   if(ok)
   {
      long posid=0; ulong dTk=trade.ResultDeal();
      if(dTk>0 && HistoryDealSelect(dTk)) posid=HistoryDealGetInteger(dTk,DEAL_POSITION_ID);
      LogOpen(estrategia,type,price,Lote,sl,tp,atr,slDist,posid);
   }
   else PrintFormat("[%s] fallo apertura: %d", estrategia, trade.ResultRetcode());
}

//====================== LAS 4 ESTRATEGIAS ===========================
// 1) TENDENCIA: rompe el canal Donchian a favor de la EMA
void CheckTrend()
{
   if(HasPos(MagTrend())) return;
   double hh=HighestHigh(Trend_Donchian,2);   // maximo de las N velas anteriores a la ultima
   double ll=LowestLow(Trend_Donchian,2);
   double c1=iClose(_Symbol,PERIOD_CURRENT,1);
   double ef=BufV(hTrendF,0,1), es=BufV(hTrendS,0,1);
   if(ef<=0||es<=0) return;
   if(c1>hh && ef>es)      OpenTrade(MagTrend(),ORDER_TYPE_BUY,"TREND");
   else if(c1<ll && ef<es) OpenTrade(MagTrend(),ORDER_TYPE_SELL,"TREND");
}
// 2) ORB: construye el rango de apertura y opera su ruptura (una vez por dia)
void ORBTick()
{
   if(!Usar_ORB) return;
   MqlDateTime st; TimeToStruct(RefTime(),st);
   if(st.day_of_year!=g_orbDay)
   { g_orbDay=st.day_of_year; g_orbHi=-1.0; g_orbLo=DBL_MAX; g_orbTraded=false; }
   int mins=st.hour*60+st.min;
   int wStart=ORB_Hora_Inicio*60, wEnd=wStart+ORB_Rango_Min;
   int wLimit=wEnd+ORB_Max_Horas*60;   // hasta cuando se permite operar la ruptura
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(mins>=wStart && mins<wEnd)      // construyendo el rango
   {
      if(ask>g_orbHi) g_orbHi=ask;
      if(bid<g_orbLo) g_orbLo=bid;
      return;
   }
   double buf=ORB_Buffer_Pts*_Point;
   if(mins>=wEnd && mins<wLimit && g_orbHi>0 && g_orbLo<DBL_MAX && !g_orbTraded && !HasPos(MagORB()))
   {
      if(bid>g_orbHi+buf)      { OpenTrade(MagORB(),ORDER_TYPE_BUY,"ORB");  g_orbTraded=true; }
      else if(ask<g_orbLo-buf) { OpenTrade(MagORB(),ORDER_TYPE_SELL,"ORB"); g_orbTraded=true; }
   }
}
// 3) MOMENTUM: ADX fuerte + direccion DI + vela a favor
void CheckMomentum()
{
   if(HasPos(MagMom())) return;
   double adx=BufV(hADX,0,1), plus=BufV(hADX,1,1), minus=BufV(hADX,2,1);
   if(adx<Mom_ADX_Min) return;
   double c1=iClose(_Symbol,PERIOD_CURRENT,1), o1=iOpen(_Symbol,PERIOD_CURRENT,1);
   if(plus>minus && c1>o1)       OpenTrade(MagMom(),ORDER_TYPE_BUY,"MOMENTUM");
   else if(minus>plus && c1<o1)  OpenTrade(MagMom(),ORDER_TYPE_SELL,"MOMENTUM");
}
// 4) PULLBACK: en tendencia, entra cuando el precio retrocede a la EMA y rebota
void CheckPullback()
{
   if(HasPos(MagPB())) return;
   double ef=BufV(hPBf,0,1), es=BufV(hPBs,0,1);
   if(ef<=0||es<=0) return;
   double c1=iClose(_Symbol,PERIOD_CURRENT,1), l1=iLow(_Symbol,PERIOD_CURRENT,1), h1=iHigh(_Symbol,PERIOD_CURRENT,1);
   if(ef>es && l1<=ef && c1>ef)      OpenTrade(MagPB(),ORDER_TYPE_BUY,"PULLBACK");   // tendencia alcista, rebote en EMA
   else if(ef<es && h1>=ef && c1<ef) OpenTrade(MagPB(),ORDER_TYPE_SELL,"PULLBACK");  // tendencia bajista
}

//====================== REGISTRO AL CIERRE ==========================
void LogClose(ulong dealTk)
{
   long magic=HistoryDealGetInteger(dealTk,DEAL_MAGIC);
   string est=StrategyName(magic);
   if(est=="?") return;
   long posid=HistoryDealGetInteger(dealTk,DEAL_POSITION_ID);
   long dt=HistoryDealGetInteger(dealTk,DEAL_TYPE);
   string dir=(dt==DEAL_TYPE_SELL)?"BUY":"SELL";
   double exitP=HistoryDealGetDouble(dealTk,DEAL_PRICE), vol=HistoryDealGetDouble(dealTk,DEAL_VOLUME);
   double profit=HistoryDealGetDouble(dealTk,DEAL_PROFIT)+HistoryDealGetDouble(dealTk,DEAL_SWAP)+HistoryDealGetDouble(dealTk,DEAL_COMMISSION);
   datetime tOut=(datetime)HistoryDealGetInteger(dealTk,DEAL_TIME);
   long reason=HistoryDealGetInteger(dealTk,DEAL_REASON);
   string motivo=(reason==DEAL_REASON_SL?"SL":(reason==DEAL_REASON_TP?"TP":(reason==DEAL_REASON_SO?"StopOut":"otro")));
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
   double pts=(entry>0)? ((dir=="BUY")?(exitP-entry):(entry-exitP))/_Point : 0.0;
   int durMin=(tIn>0)? (int)((tOut-tIn)/60) : 0;
   PrintFormat("[CIERRE %s] %s pos=%s | %.2f->%.2f | %.0f pts | PnL=%.2f | dur=%d min | %s",
      est, dir, (string)posid, entry, exitP, pts, profit, durMin, motivo);
   if(Alertas_Movil)
      SendNotification(StringFormat("%s CIERRE %s | %.0f pts | PnL %.2f | %s", est, dir, pts, profit, motivo));
   if(!Guardar_CSV) return;
   string fn="MultiEstrategia_"+_Symbol+"_cierres.csv";
   int h=FileOpen(fn, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"fecha","hora","estrategia","pos_id","dir","entrada","salida","pnl_usd","pts","dur_min","motivo","lote");
   FileSeek(h,0,SEEK_END);
   FileWrite(h, TimeToString(tOut,TIME_DATE), TimeToString(tOut,TIME_SECONDS), est, (string)posid, dir,
      DoubleToString(entry,2), DoubleToString(exitP,2), DoubleToString(profit,2),
      DoubleToString(pts,0), (string)durMin, motivo, DoubleToString(vol,2));
   FileClose(h);
}
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   ulong dealTk=trans.deal;
   if(dealTk==0 || !HistoryDealSelect(dealTk)) return;
   if(HistoryDealGetString(dealTk,DEAL_SYMBOL)!=_Symbol) return;
   if(HistoryDealGetInteger(dealTk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   LogClose(dealTk);
}

//====================== PANEL (Comment) =============================
void DayStats(long magic,int &ops,double &pnl)
{
   ops=0; pnl=0.0;
   datetime d0=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(!HistorySelect(d0,TimeCurrent()+60)) return;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
   {
      ulong tk=HistoryDealGetTicket(i);
      if(tk==0) continue;
      if(HistoryDealGetString(tk,DEAL_SYMBOL)!=_Symbol) continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=magic) continue;
      if(HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      pnl+=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_COMMISSION);
      ops++;
   }
}
string LineaEstrategia(string name,bool on,long magic)
{
   int ops; double pnl; DayStats(magic,ops,pnl);
   string pos=HasPos(magic)?"  [POS ABIERTA]":"";
   return StringFormat("  %-10s %-4s | hoy: %d ops  PnL %+.2f%s\n", name, (on?"ON":"off"), ops, pnl, pos);
}
void ShowPanel()
{
   string s="=== MULTI-ESTRATEGIA "+_Symbol+" (M5)  v1.02 ===\n";
   s+="Cada estrategia opera independiente y se etiqueta en el CSV.\n\n";
   s+=LineaEstrategia("1 TREND",   Usar_Trend,   MagTrend());
   s+=LineaEstrategia("2 ORB",     Usar_ORB,     MagORB());
   s+=LineaEstrategia("3 MOMENTUM",Usar_Momentum,MagMom());
   s+=LineaEstrategia("4 PULLBACK",Usar_Pullback,MagPB());
   s+="\nLote "+DoubleToString(Lote,2)+"  SL "+DoubleToString(SL_ATR,1)+"xATR  TP "+DoubleToString(TP_R,1)+"xSL\n";
   s+="NO es asesoria financiera. Solo para analisis.";
   Comment(s);
}

//====================== INIT / DEINIT / TICK ========================
int OnInit()
{
   hATR   = iATR(_Symbol,PERIOD_CURRENT,ATR_Periodo);
   hTrendF= iMA(_Symbol,PERIOD_CURRENT,Trend_EMA_Fast,0,MODE_EMA,PRICE_CLOSE);
   hTrendS= iMA(_Symbol,PERIOD_CURRENT,Trend_EMA_Slow,0,MODE_EMA,PRICE_CLOSE);
   hADX   = iADX(_Symbol,PERIOD_CURRENT,Mom_ADX_Periodo);
   hPBf   = iMA(_Symbol,PERIOD_CURRENT,PB_EMA_Fast,0,MODE_EMA,PRICE_CLOSE);
   hPBs   = iMA(_Symbol,PERIOD_CURRENT,PB_EMA_Slow,0,MODE_EMA,PRICE_CLOSE);
   if(hATR==INVALID_HANDLE||hTrendF==INVALID_HANDLE||hTrendS==INVALID_HANDLE||
      hADX==INVALID_HANDLE||hPBf==INVALID_HANDLE||hPBs==INVALID_HANDLE)
   { Print("Error creando indicadores"); return INIT_FAILED; }
   ShowPanel();
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   if(hATR!=INVALID_HANDLE)    IndicatorRelease(hATR);
   if(hTrendF!=INVALID_HANDLE) IndicatorRelease(hTrendF);
   if(hTrendS!=INVALID_HANDLE) IndicatorRelease(hTrendS);
   if(hADX!=INVALID_HANDLE)    IndicatorRelease(hADX);
   if(hPBf!=INVALID_HANDLE)    IndicatorRelease(hPBf);
   if(hPBs!=INVALID_HANDLE)    IndicatorRelease(hPBs);
   Comment("");
}
void OnTick()
{
   ORBTick();   // se evalua en cada tick (ruptura intrabar)
   if(EnHorario() && NewBar())
   {
      if(Usar_Trend)    CheckTrend();
      if(Usar_Momentum) CheckMomentum();
      if(Usar_Pullback) CheckPullback();
   }
   // panel throttled cada ~2s
   uint now=GetTickCount();
   if(now-g_lastPanel>2000){ g_lastPanel=now; ShowPanel(); }
}
//+------------------------------------------------------------------+
