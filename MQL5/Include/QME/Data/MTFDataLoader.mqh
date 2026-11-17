#ifndef QME_DATA_MTF_DATA_LOADER_MQH
#define QME_DATA_MTF_DATA_LOADER_MQH

#include <QME/Core/QMETypes.mqh>

#define QME_LOAD_ATTEMPTS 3
#define QME_HISTORY_NOT_FOUND 4806
#define QME_MIN_CALCULATED_BARS 20

class CQMEDataLoader
  {
private:
   string       m_symbol;
   int          m_h4_atr, m_h4_fast, m_h4_slow;
   int          m_h1_atr, m_h1_fast, m_h1_slow;
   int          m_m5_atr, m_m5_fast, m_m5_slow;
   MqlRates     m_h4_rates[], m_h1_rates[], m_m5_rates[];
   double       m_h4_atr_value, m_h4_fast_value, m_h4_slow_value;
   double       m_h1_atr_value, m_h1_fast_value, m_h1_slow_value;
   double       m_m5_atr_value, m_m5_fast_value, m_m5_slow_value;
   int          m_required_rates;
   bool         m_ready;
   bool         m_error_4806;
   string       m_reason;

   bool CreateFrameHandles(const ENUM_TIMEFRAMES tf,
                           int &atr_handle, int &fast_handle, int &slow_handle)
     {
      atr_handle=iATR(m_symbol,tf,14);
      fast_handle=iMA(m_symbol,tf,20,0,MODE_EMA,PRICE_CLOSE);
      slow_handle=iMA(m_symbol,tf,50,0,MODE_EMA,PRICE_CLOSE);
      return(atr_handle!=INVALID_HANDLE && fast_handle!=INVALID_HANDLE && slow_handle!=INVALID_HANDLE);
     }

   void ReleaseHandle(int &handle)
     {
      if(handle!=INVALID_HANDLE)
        {
         IndicatorRelease(handle);
         handle=INVALID_HANDLE;
        }
     }

   bool IsSynchronized(const ENUM_TIMEFRAMES tf)
     {
      long synchronized=0;
      ResetLastError();
      if(!SeriesInfoInteger(m_symbol,tf,SERIES_SYNCHRONIZED,synchronized) || synchronized==0)
        {
         int error=GetLastError();
         m_error_4806=(error==QME_HISTORY_NOT_FOUND);
         m_reason=StringFormat("Waiting for %s series synchronization%s",
                               EnumToString(tf),m_error_4806?" (history error 4806)":"");
         return(false);
        }
      return(true);
     }

   bool ValidateRates(const ENUM_TIMEFRAMES tf,MqlRates &rates[])
     {
      for(int i=0;i<ArraySize(rates);i++)
        {
         if(rates[i].time<=0 || !MathIsValidNumber(rates[i].open) ||
            !MathIsValidNumber(rates[i].high) || !MathIsValidNumber(rates[i].low) ||
            !MathIsValidNumber(rates[i].close) || rates[i].low<=0.0 ||
            rates[i].high<rates[i].low || rates[i].open<rates[i].low ||
            rates[i].open>rates[i].high || rates[i].close<rates[i].low ||
            rates[i].close>rates[i].high ||
            (i>0 && rates[i-1].time<=rates[i].time))
           {
            m_reason=StringFormat("Invalid or non-monotonic closed rates for %s at shift %d",
                                  EnumToString(tf),i);
            return(false);
           }
        }
      return(true);
     }

   bool CopyRatesRetry(const ENUM_TIMEFRAMES tf, MqlRates &rates[])
     {
      for(int attempt=1; attempt<=QME_LOAD_ATTEMPTS; attempt++)
        {
         ResetLastError();
         int copied=CopyRates(m_symbol,tf,1,m_required_rates,rates);
         int error=GetLastError();
         if(copied==m_required_rates)
           {
            ArraySetAsSeries(rates,true);
            if(ValidateRates(tf,rates)) return(true);
           }
         else
           {
            m_error_4806=(error==QME_HISTORY_NOT_FOUND);
            m_reason=StringFormat("CopyRates(%s) attempt %d/%d copied %d/%d%s",
                                  EnumToString(tf),attempt,QME_LOAD_ATTEMPTS,copied,m_required_rates,
                                  m_error_4806?"; history error 4806":"");
           }
        }
      return(false);
     }

   bool CopyOneBufferRetry(const int handle, const ENUM_TIMEFRAMES tf,
                           const string label, double &destination)
     {
      double values[];
      ArrayResize(values,1);
      for(int attempt=1; attempt<=QME_LOAD_ATTEMPTS; attempt++)
        {
         ResetLastError();
         int calculated=BarsCalculated(handle);
         int bars_error=GetLastError();
         if(calculated<0 || calculated<QME_MIN_CALCULATED_BARS)
           {
            m_error_4806=(bars_error==QME_HISTORY_NOT_FOUND);
            m_reason=StringFormat("BarsCalculated(%s %s)=%d%s; awaiting indicator history",
                                  EnumToString(tf),label,calculated,
                                  m_error_4806?" (error 4806)":"");
            continue;
           }
         ResetLastError();
         int copied=CopyBuffer(handle,0,1,1,values);
         int error=GetLastError();
         if(copied==1 && MathIsValidNumber(values[0]))
           {
            destination=values[0];
            return(true);
           }
         m_error_4806=(error==QME_HISTORY_NOT_FOUND);
         m_reason=StringFormat("CopyBuffer(%s %s) attempt %d/%d copied %d%s",
                               EnumToString(tf),label,attempt,QME_LOAD_ATTEMPTS,copied,
                               m_error_4806?"; history error 4806":"");
        }
      return(false);
     }

   bool LoadFrame(const ENUM_TIMEFRAMES tf,
                  const int atr_handle,const int fast_handle,const int slow_handle,
                  MqlRates &rates[],double &atr_value,double &fast_value,double &slow_value)
     {
      if(!IsSynchronized(tf))
         return(false);
      if(!CopyRatesRetry(tf,rates))
         return(false);
      if(!CopyOneBufferRetry(atr_handle,tf,"ATR",atr_value))
         return(false);
      if(!CopyOneBufferRetry(fast_handle,tf,"EMA20",fast_value))
         return(false);
      if(!CopyOneBufferRetry(slow_handle,tf,"EMA50",slow_value))
         return(false);
      if(atr_value<=0.0 || !MathIsValidNumber(atr_value))
        {
         m_reason=StringFormat("Invalid ATR value for %s",EnumToString(tf));
         return(false);
        }
      return(true);
     }

public:
   CQMEDataLoader(void)
     {
      m_h4_atr=m_h4_fast=m_h4_slow=INVALID_HANDLE;
      m_h1_atr=m_h1_fast=m_h1_slow=INVALID_HANDLE;
      m_m5_atr=m_m5_fast=m_m5_slow=INVALID_HANDLE;
      m_ready=false;
      m_error_4806=false;
      m_required_rates=100;
      m_reason="Not initialized";
     }

   bool Initialize(const string symbol,const int required_rates=100)
     {
      m_symbol=symbol;
      m_required_rates=(int)MathMax(60,required_rates);
      if(!CreateFrameHandles(PERIOD_H4,m_h4_atr,m_h4_fast,m_h4_slow) ||
         !CreateFrameHandles(PERIOD_H1,m_h1_atr,m_h1_fast,m_h1_slow) ||
         !CreateFrameHandles(PERIOD_M5,m_m5_atr,m_m5_fast,m_m5_slow))
        {
         m_reason="Unable to create timeframe indicator handles";
         Shutdown();
         return(false);
        }
      m_reason="Waiting for H4/H1/M5 history";
      return(true);
     }

   void Shutdown(void)
     {
      ReleaseHandle(m_h4_atr); ReleaseHandle(m_h4_fast); ReleaseHandle(m_h4_slow);
      ReleaseHandle(m_h1_atr); ReleaseHandle(m_h1_fast); ReleaseHandle(m_h1_slow);
      ReleaseHandle(m_m5_atr); ReleaseHandle(m_m5_fast); ReleaseHandle(m_m5_slow);
      m_ready=false;
     }

   bool Refresh(void)
     {
      m_ready=false;
      m_error_4806=false;
      if(!LoadFrame(PERIOD_H4,m_h4_atr,m_h4_fast,m_h4_slow,m_h4_rates,
                    m_h4_atr_value,m_h4_fast_value,m_h4_slow_value)) return(false);
      if(!LoadFrame(PERIOD_H1,m_h1_atr,m_h1_fast,m_h1_slow,m_h1_rates,
                    m_h1_atr_value,m_h1_fast_value,m_h1_slow_value)) return(false);
      if(!LoadFrame(PERIOD_M5,m_m5_atr,m_m5_fast,m_m5_slow,m_m5_rates,
                    m_m5_atr_value,m_m5_fast_value,m_m5_slow_value)) return(false);
      m_ready=true;
      m_reason="All required timeframe rates and buffers are ready";
      return(true);
     }

   bool Ready(void) const { return(m_ready); }
   bool ReadyNow(void)
     {
      if(!m_ready) return(false);
      if(!IsSynchronized(PERIOD_H4) || !IsSynchronized(PERIOD_H1) ||
         !IsSynchronized(PERIOD_M5))
        {
         m_ready=false;
         return(false);
        }
      return(true);
     }
   bool HadHistory4806(void) const { return(m_error_4806); }
   string Reason(void) const { return(m_reason); }
   double Atr(const ENUM_TIMEFRAMES tf) const
     {
      if(tf==PERIOD_H4) return(m_h4_atr_value);
      if(tf==PERIOD_H1) return(m_h1_atr_value);
      if(tf==PERIOD_M5) return(m_m5_atr_value);
      return(0.0);
     }
   double FastEMA(const ENUM_TIMEFRAMES tf) const
     {
      if(tf==PERIOD_H4) return(m_h4_fast_value);
      if(tf==PERIOD_H1) return(m_h1_fast_value);
      if(tf==PERIOD_M5) return(m_m5_fast_value);
      return(0.0);
     }
   double SlowEMA(const ENUM_TIMEFRAMES tf) const
     {
      if(tf==PERIOD_H4) return(m_h4_slow_value);
      if(tf==PERIOD_H1) return(m_h1_slow_value);
      if(tf==PERIOD_M5) return(m_m5_slow_value);
      return(0.0);
     }
   int RateCount(const ENUM_TIMEFRAMES tf) const
     {
      if(tf==PERIOD_H4) return(ArraySize(m_h4_rates));
      if(tf==PERIOD_H1) return(ArraySize(m_h1_rates));
      if(tf==PERIOD_M5) return(ArraySize(m_m5_rates));
      return(0);
     }
   bool GetRate(const ENUM_TIMEFRAMES tf,const int shift,MqlRates &bar) const
     {
      if(shift<0 || shift>=RateCount(tf)) return(false);
      if(tf==PERIOD_H4) bar=m_h4_rates[shift];
      else if(tf==PERIOD_H1) bar=m_h1_rates[shift];
      else if(tf==PERIOD_M5) bar=m_m5_rates[shift];
      else return(false);
      return(true);
     }
   double TickSize(void) const
     {
      double tick=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tick<=0.0) tick=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      return(tick);
     }
   double PointSize(void) const { return(SymbolInfoDouble(m_symbol,SYMBOL_POINT)); }
  };

#endif // QME_DATA_MTF_DATA_LOADER_MQH
