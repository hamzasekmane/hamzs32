#ifndef QME_CORE_TYPES_MQH
#define QME_CORE_TYPES_MQH

enum QME_DIRECTION
  {
   QME_DIRECTION_SELL = -1,
   QME_DIRECTION_NONE = 0,
   QME_DIRECTION_BUY = 1
  };

#define QME_ZONE_ORDER_BLOCK 1
#define QME_ZONE_FVG         2
#define QME_ZONE_SWEEP       4
#define QME_ZONE_DISCOUNT    8

struct QMEZone
  {
   double low;
   double high;
   int direction;
   int features;
   double strength;
   datetime formed;
  };

struct QMEAnalysis
  {
   int bias;
   bool entry_allowed;
   int zone_count;
   double probability;
   double entry;
   double stop;
   double target;
   double rr;
   string reason;
   string explanation;
  };

#endif // QME_CORE_TYPES_MQH
