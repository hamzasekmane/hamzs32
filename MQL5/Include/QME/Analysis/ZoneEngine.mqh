#ifndef QME_ANALYSIS_ZONE_ENGINE_MQH
#define QME_ANALYSIS_ZONE_ENGINE_MQH

#include <QME/Core/QMETypes.mqh>
#include <QME/Core/QMEFeatureLogic.mqh>
#include <QME/Data/MTFDataLoader.mqh>

#define QME_MAX_ZONES 40

class CQMEZoneEngine
  {
private:
   QMEZone m_zones[QME_MAX_ZONES];
   int     m_count;
   int     m_ob_count,m_fvg_count,m_sweep_count;
   string  m_reason;

   double RoundToTick(const double price,const double tick)
     {
      return(QMERoundToTick(price,tick,tick));
     }

   double StrengthFor(const int features)
     {
      return(QMEZoneStrength(features));
     }

   void AddCandidate(const double raw_low,const double raw_high,const int direction,
                     const int feature,const datetime formed,const double atr,
                     const double range_mid,const double tick)
     {
      double low=RoundToTick(MathMin(raw_low,raw_high),tick);
      double high=RoundToTick(MathMax(raw_low,raw_high),tick);
      if(high<=low || atr<=0.0) return;
      int flags=feature;
      double center=(low+high)*0.5;
      if((direction==QME_DIRECTION_BUY && center<range_mid) ||
         (direction==QME_DIRECTION_SELL && center>range_mid))
         flags|=QME_ZONE_DISCOUNT;

      double merge_distance=MathMax(tick,atr*0.12);
      for(int i=0;i<m_count;i++)
        {
         if(m_zones[i].direction!=direction) continue;
         if(low>m_zones[i].high+merge_distance || high<m_zones[i].low-merge_distance) continue;
         m_zones[i].low=RoundToTick(MathMin(m_zones[i].low,low),tick);
         m_zones[i].high=RoundToTick(MathMax(m_zones[i].high,high),tick);
         m_zones[i].features|=flags;
         m_zones[i].strength=StrengthFor(m_zones[i].features);
         if(formed>m_zones[i].formed) m_zones[i].formed=formed;
         return;
        }
      if(m_count>=QME_MAX_ZONES) return;
      m_zones[m_count].low=low;
      m_zones[m_count].high=high;
      m_zones[m_count].direction=direction;
      m_zones[m_count].features=flags;
      m_zones[m_count].strength=StrengthFor(flags);
      m_zones[m_count].formed=formed;
      m_count++;
     }

   void ScanTimeframe(CQMEDataLoader &data,const ENUM_TIMEFRAMES tf)
     {
      int count=data.RateCount(tf);
      double atr=data.Atr(tf);
      if(count<5 || atr<=0.0) return;
      double tick=MathMax(data.TickSize(),data.PointSize());
      double range_low=DBL_MAX,range_high=-DBL_MAX;
      int range_count=(int)MathMin(count,30);
      for(int i=0;i<range_count;i++)
        {
         MqlRates b;
         if(!data.GetRate(tf,i,b)) continue;
         range_low=MathMin(range_low,b.low);
         range_high=MathMax(range_high,b.high);
        }
      if(range_low>=range_high) return;
      double range_mid=(range_low+range_high)*0.5;
      int max_index=(int)MathMin(count-1,40);

      // Order block: opposing candle followed by an ATR-sized displacement candle.
      for(int i=2;i<=max_index;i++)
        {
         MqlRates base,impulse;
         if(!data.GetRate(tf,i,base) || !data.GetRate(tf,i-1,impulse)) continue;
         if(QMEOrderBlockValid(base.open,base.close,base.high,base.low,
                               impulse.close,QME_DIRECTION_BUY,atr))
           {
            AddCandidate(base.low,base.high,QME_DIRECTION_BUY,QME_ZONE_ORDER_BLOCK,
                         base.time,atr,range_mid,tick);
            m_ob_count++;
           }
         if(QMEOrderBlockValid(base.open,base.close,base.high,base.low,
                               impulse.close,QME_DIRECTION_SELL,atr))
           {
            AddCandidate(base.low,base.high,QME_DIRECTION_SELL,QME_ZONE_ORDER_BLOCK,
                         base.time,atr,range_mid,tick);
            m_ob_count++;
           }
        }

      // Three-candle fair value gap; indices are series-oriented, zero is most recent closed bar.
      for(int i=2;i<=max_index;i++)
        {
         MqlRates newer,older;
         double zone_low=0.0,zone_high=0.0;
         if(!data.GetRate(tf,i-2,newer) || !data.GetRate(tf,i,older)) continue;
         if(QMEDetectFVG(older.high,older.low,newer.high,newer.low,
                         QME_DIRECTION_BUY,atr,data.TickSize(),data.PointSize(),0.10,
                         zone_low,zone_high))
           {
            AddCandidate(zone_low,zone_high,QME_DIRECTION_BUY,QME_ZONE_FVG,
                         newer.time,atr,range_mid,tick);
            m_fvg_count++;
           }
         if(QMEDetectFVG(older.high,older.low,newer.high,newer.low,
                         QME_DIRECTION_SELL,atr,data.TickSize(),data.PointSize(),0.10,
                         zone_low,zone_high))
           {
            AddCandidate(zone_low,zone_high,QME_DIRECTION_SELL,QME_ZONE_FVG,
                         newer.time,atr,range_mid,tick);
            m_fvg_count++;
           }
        }

      // Liquidity sweep: a closed candle trades through a prior range extreme and closes back inside.
      MqlRates latest;
      if(!data.GetRate(tf,0,latest)) return;
      double swing_low=DBL_MAX,swing_high=-DBL_MAX;
      int lookback=(int)MathMin(count-1,12);
      for(int j=1;j<=lookback;j++)
        {
         MqlRates prior;
         if(!data.GetRate(tf,j,prior)) continue;
         swing_low=MathMin(swing_low,prior.low);
         swing_high=MathMax(swing_high,prior.high);
        }
      if(swing_low<DBL_MAX && QMESweepValid(latest.low,latest.high,latest.close,
                                             swing_low,swing_high,QME_DIRECTION_BUY))
        {
         AddCandidate(latest.low,swing_low,QME_DIRECTION_BUY,QME_ZONE_SWEEP,
                      latest.time,atr,range_mid,tick);
         m_sweep_count++;
        }
      if(swing_high>-DBL_MAX && QMESweepValid(latest.low,latest.high,latest.close,
                                               swing_low,swing_high,QME_DIRECTION_SELL))
        {
         AddCandidate(swing_high,latest.high,QME_DIRECTION_SELL,QME_ZONE_SWEEP,
                      latest.time,atr,range_mid,tick);
         m_sweep_count++;
        }
     }

public:
   CQMEZoneEngine(void) { Reset(); }

   void Reset(void)
     {
      m_count=0;
      m_ob_count=0;
      m_fvg_count=0;
      m_sweep_count=0;
      m_reason="No zones scanned";
     }

   void Build(CQMEDataLoader &data)
     {
      Reset();
      if(!data.ReadyNow())
        {
         m_reason="Zone scan deferred: required timeframe data is not ready";
         return;
        }
      ScanTimeframe(data,PERIOD_H4);
      ScanTimeframe(data,PERIOD_H1);
      if(m_count==0)
         m_reason=StringFormat("No zones: no qualifying OB displacement, ATR-sized FVG, or reclaimed liquidity sweep (OB=%d FVG=%d sweeps=%d)",
                               m_ob_count,m_fvg_count,m_sweep_count);
      else
         m_reason=StringFormat("%d zones from H4/H1 (OB=%d FVG=%d sweeps=%d)",
                               m_count,m_ob_count,m_fvg_count,m_sweep_count);
     }

   int Count(void) const { return(m_count); }
   int OrderBlockCount(void) const { return(m_ob_count); }
   int FVGCount(void) const { return(m_fvg_count); }
   int SweepCount(void) const { return(m_sweep_count); }
   string Reason(void) const { return(m_reason); }
   bool Get(const int index,QMEZone &zone) const
     {
      if(index<0 || index>=m_count) return(false);
      zone=m_zones[index];
      return(true);
     }
   string Grade(const QMEZone &zone) const
     {
      return(QMEZoneGrade(zone.strength));
     }
  };

#endif // QME_ANALYSIS_ZONE_ENGINE_MQH
