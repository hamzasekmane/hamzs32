#property strict
#property script_show_inputs

#include <QME/Core/QMEFeatureLogic.mqh>

int g_failures=0;
int g_assertions=0;

void Check(const string name,const bool passed)
  {
   g_assertions++;
   if(passed) Print("[PASS] ",name);
   else
     {
      g_failures++;
      Print("[FAIL] ",name);
     }
  }

void OnStart(void)
  {
   double low=0.0,high=0.0;
   Check("bullish FVG price bounds",
         QMEDetectFVG(100.0,98.0,105.0,102.0,QME_DIRECTION_BUY,
                      2.0,0.01,0.01,0.10,low,high) &&
         MathAbs(low-100.0)<1e-8 && MathAbs(high-102.0)<1e-8);
   Check("bearish FVG price bounds",
         QMEDetectFVG(104.0,101.0,99.0,96.0,QME_DIRECTION_SELL,
                      2.0,0.01,0.01,0.10,low,high) &&
         MathAbs(low-99.0)<1e-8 && MathAbs(high-101.0)<1e-8);
   Check("FVG rejects sub-threshold gap",
         !QMEDetectFVG(100.0,98.0,100.1,100.05,QME_DIRECTION_BUY,
                       2.0,0.01,0.01,0.10,low,high));
   Check("order block requires ATR displacement",
         QMEOrderBlockValid(10.0,9.8,10.2,9.7,10.8,QME_DIRECTION_BUY,1.0));
   Check("order block rejects weak displacement",
         !QMEOrderBlockValid(10.0,9.8,10.2,9.7,10.3,QME_DIRECTION_BUY,1.0));
   Check("bullish liquidity sweep reclaims low",
         QMESweepValid(8.8,10.2,9.7,9.0,11.0,QME_DIRECTION_BUY));
   Check("bearish liquidity sweep reclaims high",
         QMESweepValid(9.8,11.4,10.8,9.0,11.0,QME_DIRECTION_SELL));
   Check("premium discount features grade A",
         QMEZoneGrade(QMEZoneStrength(QME_ZONE_ORDER_BLOCK|QME_ZONE_FVG|
                                     QME_ZONE_SWEEP|QME_ZONE_DISCOUNT))=="A");
   Check("feature score is bounded and explainable",
         MathAbs(QMEEntryScore(100.0,true,true,true,true,true)-100.0)<1e-8);
   Check("RR gate accepts 2R and rejects below 1.5R",
         QMERiskReward(100.0,98.0,104.0)>=1.5 &&
         QMERiskReward(100.0,98.0,102.0)<1.5);
   Check("tick rounding uses broker tick increments",
         MathAbs(QMERoundToTick(1.083456,0.00001,0.00001)-1.08346)<1e-8);

   Print("QME feature tests: ",g_assertions," assertions, ",g_failures," failures.");
   if(g_failures==0) Print("QME feature tests PASSED.");
   else Print("QME feature tests FAILED.");
  }
