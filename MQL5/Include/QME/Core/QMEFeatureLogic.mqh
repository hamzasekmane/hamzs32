#ifndef QME_CORE_FEATURE_LOGIC_MQH
#define QME_CORE_FEATURE_LOGIC_MQH

#include <QME/Core/QMETypes.mqh>

double QMEEffectiveTick(const double tick_size,const double point)
  {
   return(MathMax(tick_size,point));
  }

double QMERoundToTick(const double price,const double tick_size,const double point)
  {
   double tick=QMEEffectiveTick(tick_size,point);
   if(tick<=0.0) return(price);
   return(MathRound(price/tick)*tick);
  }

bool QMEDetectFVG(const double older_high,const double older_low,
                  const double newer_high,const double newer_low,
                  const int direction,const double atr,const double tick_size,
                  const double point,const double min_gap_atr,
                  double &zone_low,double &zone_high)
  {
   double threshold=MathMax(QMEEffectiveTick(tick_size,point),atr*min_gap_atr);
   if(direction==QME_DIRECTION_BUY && newer_low-older_high>=threshold)
     { zone_low=older_high; zone_high=newer_low; return(true); }
   if(direction==QME_DIRECTION_SELL && older_low-newer_high>=threshold)
     { zone_low=newer_high; zone_high=older_low; return(true); }
   return(false);
  }

bool QMEOrderBlockValid(const double base_open,const double base_close,
                        const double base_high,const double base_low,
                        const double impulse_close,const int direction,
                        const double atr)
  {
   if(direction==QME_DIRECTION_BUY)
      return(base_close<base_open && impulse_close>base_high && impulse_close-base_high>=atr*0.45);
   if(direction==QME_DIRECTION_SELL)
      return(base_close>base_open && impulse_close<base_low && base_low-impulse_close>=atr*0.45);
   return(false);
  }

bool QMESweepValid(const double current_low,const double current_high,
                   const double current_close,const double swing_low,
                   const double swing_high,const int direction)
  {
   if(direction==QME_DIRECTION_BUY) return(current_low<swing_low && current_close>swing_low);
   if(direction==QME_DIRECTION_SELL) return(current_high>swing_high && current_close<swing_high);
   return(false);
  }

double QMEZoneStrength(const int features)
  {
   double value=0.0;
   if((features & QME_ZONE_ORDER_BLOCK)!=0) value+=35.0;
   if((features & QME_ZONE_FVG)!=0) value+=25.0;
   if((features & QME_ZONE_SWEEP)!=0) value+=25.0;
   if((features & QME_ZONE_DISCOUNT)!=0) value+=15.0;
   return(MathMin(100.0,value));
  }

string QMEZoneGrade(const double strength)
  {
   if(strength>=80.0) return("A");
   if(strength>=60.0) return("B");
   if(strength>=40.0) return("C");
   return("D");
  }

double QMEEntryScore(const double zone_strength,const bool aligned_bias,
                     const bool has_fvg,const bool has_sweep,
                     const bool premium_discount,const bool m5_confirmed)
  {
   double value=(aligned_bias?20.0:0.0)+zone_strength*0.25+
                (has_fvg?15.0:0.0)+(has_sweep?15.0:0.0)+
                (premium_discount?10.0:0.0)+(m5_confirmed?15.0:0.0);
   return(MathMin(100.0,value));
  }

double QMERiskReward(const double entry,const double stop,const double target)
  {
   double risk=MathAbs(entry-stop);
   double reward=MathAbs(target-entry);
   if(risk<=0.0 || reward<=0.0) return(0.0);
   return(reward/risk);
  }

#endif // QME_CORE_FEATURE_LOGIC_MQH
