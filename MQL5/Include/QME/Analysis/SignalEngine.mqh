#ifndef QME_ANALYSIS_SIGNAL_ENGINE_MQH
#define QME_ANALYSIS_SIGNAL_ENGINE_MQH

#include <QME/Core/QMETypes.mqh>
#include <QME/Core/QMEFeatureLogic.mqh>
#include <QME/Data/MTFDataLoader.mqh>
#include <QME/Analysis/ZoneEngine.mqh>

class CQMESignalEngine
  {
private:
   int Trend(const ENUM_TIMEFRAMES tf,CQMEDataLoader &data)
     {
      MqlRates last;
      if(!data.GetRate(tf,0,last)) return(QME_DIRECTION_NONE);
      if(last.close>data.FastEMA(tf) && data.FastEMA(tf)>data.SlowEMA(tf))
         return(QME_DIRECTION_BUY);
      if(last.close<data.FastEMA(tf) && data.FastEMA(tf)<data.SlowEMA(tf))
         return(QME_DIRECTION_SELL);
      return(QME_DIRECTION_NONE);
     }

   int Bias(CQMEDataLoader &data)
     {
      int h4=Trend(PERIOD_H4,data);
      int h1=Trend(PERIOD_H1,data);
      if(h4!=QME_DIRECTION_NONE && h4==h1) return(h4);
      return(QME_DIRECTION_NONE);
     }

   bool M5Confirmed(const int direction,CQMEDataLoader &data)
     {
      MqlRates last,previous;
      if(!data.GetRate(PERIOD_M5,0,last) || !data.GetRate(PERIOD_M5,1,previous)) return(false);
      if(direction==QME_DIRECTION_BUY)
         return(last.close>last.open && last.close>=previous.close &&
                last.close>data.FastEMA(PERIOD_M5) &&
                data.FastEMA(PERIOD_M5)>data.SlowEMA(PERIOD_M5));
      if(direction==QME_DIRECTION_SELL)
         return(last.close<last.open && last.close<=previous.close &&
                last.close<data.FastEMA(PERIOD_M5) &&
                data.FastEMA(PERIOD_M5)<data.SlowEMA(PERIOD_M5));
      return(false);
     }

   bool SelectZone(const int direction,const double price,const double tolerance,
                   CQMEZoneEngine &zones,QMEZone &selected)
     {
      double best=DBL_MAX;
      bool found=false;
      for(int i=0;i<zones.Count();i++)
        {
         QMEZone zone;
         if(!zones.Get(i,zone) || zone.direction!=direction) continue;
         double distance=0.0;
         if(price<zone.low) distance=zone.low-price;
         else if(price>zone.high) distance=price-zone.high;
         if(distance<=tolerance && distance<best)
           {
            best=distance;
            selected=zone;
            found=true;
           }
        }
      return(found);
     }

   bool FindTarget(const int direction,const double entry,CQMEDataLoader &data,
                   CQMEZoneEngine &zones,double &target)
     {
      double best=DBL_MAX;
      bool found=false;
      for(int i=0;i<zones.Count();i++)
        {
         QMEZone zone;
         if(!zones.Get(i,zone)) continue;
         if(direction==QME_DIRECTION_BUY && zone.direction==QME_DIRECTION_SELL && zone.low>entry)
           {
            double distance=zone.low-entry;
            if(distance<best) { best=distance; target=zone.low; found=true; }
           }
         if(direction==QME_DIRECTION_SELL && zone.direction==QME_DIRECTION_BUY && zone.high<entry)
           {
            double distance=entry-zone.high;
            if(distance<best) { best=distance; target=zone.high; found=true; }
           }
        }
      if(found) return(true);

      // If no opposing zone exists, use the nearest valid H4 range extreme as a structural target.
      int count=(int)MathMin(data.RateCount(PERIOD_H4),30);
      best=DBL_MAX;
      for(int j=1;j<count;j++)
        {
         MqlRates bar;
         if(!data.GetRate(PERIOD_H4,j,bar)) continue;
         if(direction==QME_DIRECTION_BUY && bar.high>entry && bar.high-entry<best)
           { best=bar.high-entry; target=bar.high; found=true; }
         if(direction==QME_DIRECTION_SELL && bar.low<entry && entry-bar.low<best)
           { best=entry-bar.low; target=bar.low; found=true; }
        }
      return(found);
     }

public:
   // Caller must pass through the runtime ReadyNow() gate before evaluation.
   void Evaluate(CQMEDataLoader &data,CQMEZoneEngine &zones,const double price,
                 const double minimum_probability,const double minimum_rr,
                 QMEAnalysis &result)
     {
      result.bias=QME_DIRECTION_NONE;
      result.entry_allowed=false;
      result.zone_count=zones.Count();
      result.probability=0.0;
      result.entry=price;
      result.stop=0.0;
      result.target=0.0;
      result.rr=0.0;
      result.explanation="No score: data or setup not ready";
      if(price<=0.0 || !MathIsValidNumber(price))
        {
         result.reason="No entry: current symbol quote is unavailable or invalid";
         return;
        }
      if(zones.Count()==0)
        {
         result.reason="No entry: "+zones.Reason();
         return;
        }

      result.bias=Bias(data);
      if(result.bias==QME_DIRECTION_NONE)
        {
         result.reason="No entry: H4 and H1 EMA/close structure is neutral or not aligned";
         return;
        }

      double tick=MathMax(data.TickSize(),data.PointSize());
      double atr=data.Atr(PERIOD_M5);
      double tolerance=MathMax(tick*2.0,atr*0.20);
      QMEZone selected;
      if(!SelectZone(result.bias,price,tolerance,zones,selected))
        {
         result.reason=StringFormat("No entry: no %s zone at/near price (tolerance %.8f); %s",
                                    result.bias==QME_DIRECTION_BUY?"demand":"supply",
                                    tolerance,zones.Reason());
         return;
        }
      if(!M5Confirmed(result.bias,data))
        {
         result.reason="No entry: selected zone lacks a confirming closed M5 candle";
         return;
        }
      if(!FindTarget(result.bias,price,data,zones,result.target))
        {
         result.reason="No entry: no opposing zone or valid H4 structural target beyond entry";
         return;
        }

      double stop_buffer=MathMax(tick,atr*0.10);
      if(result.bias==QME_DIRECTION_BUY) result.stop=selected.low-stop_buffer;
      else result.stop=selected.high+stop_buffer;
      double risk=MathAbs(price-result.stop);
      double reward=MathAbs(result.target-price);
      if(risk<=tick || reward<=0.0)
        {
         result.reason="No entry: invalid stop distance or non-positive target distance";
         return;
        }
      result.rr=QMERiskReward(price,result.stop,result.target);

      double bias_points=20.0;
      double zone_points=selected.strength*0.25;
      double fvg_points=(selected.features & QME_ZONE_FVG)!=0?15.0:0.0;
      double sweep_points=(selected.features & QME_ZONE_SWEEP)!=0?15.0:0.0;
      double location_points=(selected.features & QME_ZONE_DISCOUNT)!=0?10.0:0.0;
      double m5_points=15.0;
      result.probability=QMEEntryScore(selected.strength,true,
                                       (selected.features & QME_ZONE_FVG)!=0,
                                       (selected.features & QME_ZONE_SWEEP)!=0,
                                       (selected.features & QME_ZONE_DISCOUNT)!=0,true);
      string grade=zones.Grade(selected);
      result.explanation=StringFormat("Score %.0f/100 = bias %.0f + zone %.0f (grade %s, strength %.0f) + FVG %.0f + sweep %.0f + premium/discount %.0f + M5 %.0f",
                                      result.probability,bias_points,zone_points,grade,
                                      selected.strength,fvg_points,sweep_points,
                                      location_points,m5_points);
      if(result.rr<minimum_rr)
        {
         result.reason=StringFormat("No entry: RR %.2f is below minimum %.2f",result.rr,minimum_rr);
         return;
        }
      if(result.probability<minimum_probability)
        {
         result.reason=StringFormat("No entry: score %.0f is below minimum %.0f",result.probability,minimum_probability);
         return;
        }
      result.entry_allowed=true;
      result.reason=StringFormat("Entry conditions met: %s zone grade %s",
                                 result.bias==QME_DIRECTION_BUY?"demand":"supply",grade);
     }
  };

#endif // QME_ANALYSIS_SIGNAL_ENGINE_MQH
