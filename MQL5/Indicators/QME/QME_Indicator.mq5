#property strict
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2
#property indicator_type1   DRAW_ARROW
#property indicator_type2   DRAW_ARROW
#property indicator_color1  clrLimeGreen
#property indicator_color2  clrTomato
#property indicator_width1  2
#property indicator_width2  2
#property indicator_label1  "QME demand signal"
#property indicator_label2  "QME supply signal"

#include <QME/Data/MTFDataLoader.mqh>
#include <QME/Analysis/ZoneEngine.mqh>
#include <QME/Analysis/SignalEngine.mqh>

input int    InpRequiredHistoryBars = 100;
input int    InpTimerSeconds        = 2;
input double InpMinimumScore        = 65.0;
input double InpMinimumRR           = 1.50;
input bool   InpDrawZones           = true;

#define QME_OBJECT_PREFIX "QME_MTF_"

double BuySignalBuffer[];
double SellSignalBuffer[];

CQMEDataLoader  g_data;
CQMEZoneEngine  g_zones;
CQMESignalEngine g_signals;
QMEAnalysis     g_analysis;
int             g_drawn_zones=0;
bool            g_initialized=false;

string BiasText(const int bias)
  {
   if(bias==QME_DIRECTION_BUY) return("Bullish");
   if(bias==QME_DIRECTION_SELL) return("Bearish");
   return("Neutral");
  }

void SetSignalBuffers(void)
  {
   if(ArraySize(BuySignalBuffer)>0) BuySignalBuffer[0]=EMPTY_VALUE;
   if(ArraySize(SellSignalBuffer)>0) SellSignalBuffer[0]=EMPTY_VALUE;
   if(!g_analysis.entry_allowed) return;
   if(g_analysis.bias==QME_DIRECTION_BUY && ArraySize(BuySignalBuffer)>0)
      BuySignalBuffer[0]=g_analysis.entry;
   if(g_analysis.bias==QME_DIRECTION_SELL && ArraySize(SellSignalBuffer)>0)
      SellSignalBuffer[0]=g_analysis.entry;
  }

void DrawAnalysis(void)
  {
   for(int i=0;i<g_drawn_zones;i++)
      ObjectDelete(0,QME_OBJECT_PREFIX+"zone_"+IntegerToString(i));
   g_drawn_zones=0;
   if(InpDrawZones && g_data.ReadyNow())
     {
      int seconds=PeriodSeconds((ENUM_TIMEFRAMES)_Period);
      if(seconds<=0) seconds=60;
      datetime right=TimeCurrent()+seconds*30;
      for(int i=0;i<g_zones.Count();i++)
        {
         QMEZone zone;
         if(!g_zones.Get(i,zone)) continue;
         string name=QME_OBJECT_PREFIX+"zone_"+IntegerToString(i);
         datetime left=zone.formed;
         if(left<=0 || left>TimeCurrent()) left=TimeCurrent()-seconds*30;
         if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,left,zone.high,right,zone.low)) continue;
         ObjectSetInteger(0,name,OBJPROP_COLOR,
                          zone.direction==QME_DIRECTION_BUY?clrDarkGreen:clrMaroon);
         ObjectSetInteger(0,name,OBJPROP_BACK,true);
         ObjectSetInteger(0,name,OBJPROP_FILL,true);
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
         ObjectSetString(0,name,OBJPROP_TOOLTIP,
                         StringFormat("QME %s %s zone | strength %.0f/100",
                                      zone.direction==QME_DIRECTION_BUY?"demand":"supply",
                                      g_zones.Grade(zone),zone.strength));
         g_drawn_zones++;
        }
     }
   string target_name=QME_OBJECT_PREFIX+"target";
   if(g_analysis.target>0.0)
     {
      if(ObjectFind(0,target_name)<0) ObjectCreate(0,target_name,OBJ_HLINE,0,0,g_analysis.target);
      ObjectSetDouble(0,target_name,OBJPROP_PRICE,g_analysis.target);
      ObjectSetInteger(0,target_name,OBJPROP_COLOR,clrDodgerBlue);
      ObjectSetInteger(0,target_name,OBJPROP_STYLE,STYLE_DASH);
      ObjectSetString(0,target_name,OBJPROP_TOOLTIP,"QME structural target");
     }
   else ObjectDelete(0,target_name);
   ChartRedraw(0);
  }

void UpdateAnalysis(void)
  {
   if(!g_data.ReadyNow())
     {
      g_analysis.entry_allowed=false;
      g_analysis.bias=QME_DIRECTION_NONE;
      g_analysis.zone_count=0;
      g_analysis.probability=0.0;
      g_analysis.entry=0.0;
      g_analysis.stop=0.0;
      g_analysis.target=0.0;
      g_analysis.rr=0.0;
      g_analysis.reason="No entry: "+g_data.Reason();
      g_analysis.explanation="Analysis deferred until H4/H1/M5 data and buffers are ready";
      SetSignalBuffers();
      Comment("QuantumMarketEngine | Analysis only (no trading)\n",
              "Data: WAITING | ",g_data.Reason(),"\n",
              "No calculation performed until required data is ready.");
      DrawAnalysis();
      return;
     }

   g_zones.Build(g_data);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(bid<=0.0) bid=SymbolInfoDouble(_Symbol,SYMBOL_LAST);
   g_signals.Evaluate(g_data,g_zones,bid,InpMinimumScore,InpMinimumRR,g_analysis);
   SetSignalBuffers();
   Comment("QuantumMarketEngine | Analysis only (no trading)\n",
           "Data: READY | Bias: ",BiasText(g_analysis.bias)," | Zones: ",g_analysis.zone_count,"\n",
           "Entry probability score: ",DoubleToString(g_analysis.probability,0),"/100 | RR: ",
           DoubleToString(g_analysis.rr,2)," | Entry gate: ",
           g_analysis.entry_allowed?"PASS":"NO ENTRY","\n",
           g_analysis.explanation,"\n",
           g_analysis.reason,"\n",
           "Zone scan: ",g_zones.Reason());
   DrawAnalysis();
  }

int OnInit(void)
  {
   if(!MathIsValidNumber(InpMinimumScore) || InpMinimumScore<0.0 || InpMinimumScore>100.0 ||
      !MathIsValidNumber(InpMinimumRR) || InpMinimumRR<=0.0)
      return(INIT_PARAMETERS_INCORRECT);

   SetIndexBuffer(0,BuySignalBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,SellSignalBuffer,INDICATOR_DATA);
   ArraySetAsSeries(BuySignalBuffer,true);
   ArraySetAsSeries(SellSignalBuffer,true);
   PlotIndexSetInteger(0,PLOT_ARROW,233);
   PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME,"QME MTF Analysis (no trading)");

   if(!g_data.Initialize(_Symbol,InpRequiredHistoryBars))
     {
      Print("QME initialization failed: ",g_data.Reason());
      return(INIT_FAILED);
     }
   int timer_seconds=(int)MathMax(1,InpTimerSeconds);
   if(!EventSetTimer(timer_seconds))
     {
      Print("QME could not start readiness timer; error ",GetLastError());
      g_data.Shutdown();
      return(INIT_FAILED);
     }
   g_initialized=true;
   g_data.Refresh();
   UpdateAnalysis();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_data.Shutdown();
   for(int i=0;i<g_drawn_zones;i++)
      ObjectDelete(0,QME_OBJECT_PREFIX+"zone_"+IntegerToString(i));
   ObjectDelete(0,QME_OBJECT_PREFIX+"target");
   Comment("");
   g_initialized=false;
  }

void OnTimer(void)
  {
   if(!g_initialized) return;
   // Each timer event retries synchronization, rates, BarsCalculated and buffers.
   g_data.Refresh();
   UpdateAnalysis();
  }

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   if(rates_total<=0) return(0);
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   if(prev_calculated==0)
     {
      for(int i=0;i<rates_total;i++)
        {
         BuySignalBuffer[i]=EMPTY_VALUE;
         SellSignalBuffer[i]=EMPTY_VALUE;
        }
     }
   else
     {
      BuySignalBuffer[0]=EMPTY_VALUE;
      SellSignalBuffer[0]=EMPTY_VALUE;
     }

   // No analysis is performed here until the timer has made every required series ready.
   if(!g_data.ReadyNow())
     {
      Comment("QuantumMarketEngine | Analysis only (no trading)\n",
              "Data: WAITING | ",g_data.Reason(),"\n",
              "No calculation performed until required data is ready.");
      return(rates_total);
     }
   UpdateAnalysis();
   return(rates_total);
  }
