
//+------------------------------------------------------------------+
//|              Nkateko Three Candle Scalper v1.0                  |
//|              MetaTrader 5 - MQL5                                |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

//--- Inputs
input double RiskPercent       = 0.5;
input double RiskReward        = 2.0;
input int    EMAPeriod         = 10;
input int    MaxTrades         = 2;
input double StopBufferPips    = 1.0;
input double MaxSpreadPips     = 2.0;
input ulong  MagicNumber       = 17082026;
input int    SlippagePoints    = 20;

//--- Global variables
int emaHandle = INVALID_HANDLE;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Pip size                                                         |
//+------------------------------------------------------------------+
double PipSize()
{
   if(_Digits == 3 || _Digits == 5)
      return _Point * 10.0;

   return _Point;
}

//+------------------------------------------------------------------+
//| Count open EA positions                                          |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         count++;
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| Calculate lot size from stop distance                            |
//+------------------------------------------------------------------+
double CalculateLot(ENUM_ORDER_TYPE type,
                    double entry,
                    double sl)
{
   double riskMoney =
      AccountInfoDouble(ACCOUNT_EQUITY) *
      RiskPercent / 100.0;

   double loss = 0.0;

   if(!OrderCalcProfit(type, _Symbol, 1.0,
                       entry, sl, loss))
      return 0.0;

   double lossPerLot = MathAbs(loss);

   if(lossPerLot <= 0.0)
      return 0.0;

   double rawLot = riskMoney / lossPerLot;

   double minLot = SymbolInfoDouble(
      _Symbol, SYMBOL_VOLUME_MIN);

   double maxLot = SymbolInfoDouble(
      _Symbol, SYMBOL_VOLUME_MAX);

   double step = SymbolInfoDouble(
      _Symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0 || rawLot < minLot)
      return 0.0;

   double lot = MathFloor(rawLot / step) * step;

   lot = MathMin(lot, maxLot);

   int digits = 0;
   double temp = step;

   while(temp < 1.0 && digits < 8)
   {
      temp *= 10.0;
      digits++;
   }

   return NormalizeDouble(lot, digits);
}

//+------------------------------------------------------------------+
//| BUY setup                                                        |
//+------------------------------------------------------------------+
bool BuySignal(double ema)
{
   // Candle 3 = shift 1
   // Candle 2 = shift 2
   // Candle 1 = shift 3

   double o1 = iOpen(_Symbol, PERIOD_M5, 3);
   double c1 = iClose(_Symbol, PERIOD_M5, 3);

   double o2 = iOpen(_Symbol, PERIOD_M5, 2);
   double c2 = iClose(_Symbol, PERIOD_M5, 2);

   double o3 = iOpen(_Symbol, PERIOD_M5, 1);
   double c3 = iClose(_Symbol, PERIOD_M5, 1);

   double h1 = iHigh(_Symbol, PERIOD_M5, 3);
   double h2 = iHigh(_Symbol, PERIOD_M5, 2);

   bool bearish1 = c1 < o1;
   bool bearish2 = c2 < o2;
   bool bullish3 = c3 > o3;

   bool breakout = c3 > MathMax(h1, h2);
   bool emaConfirm = c3 > ema;

   return bearish1 && bearish2 &&
          bullish3 && breakout && emaConfirm;
}

//+------------------------------------------------------------------+
//| SELL setup                                                       |
//+------------------------------------------------------------------+
bool SellSignal(double ema)
{
   double o1 = iOpen(_Symbol, PERIOD_M5, 3);
   double c1 = iClose(_Symbol, PERIOD_M5, 3);

   double o2 = iOpen(_Symbol, PERIOD_M5, 2);
   double c2 = iClose(_Symbol, PERIOD_M5, 2);

   double o3 = iOpen(_Symbol, PERIOD_M5, 1);
   double c3 = iClose(_Symbol, PERIOD_M5, 1);

   double l1 = iLow(_Symbol, PERIOD_M5, 3);
   double l2 = iLow(_Symbol, PERIOD_M5, 2);

   bool bullish1 = c1 > o1;
   bool bullish2 = c2 > o2;
   bool bearish3 = c3 < o3;

   bool breakout = c3 < MathMin(l1, l2);
   bool emaConfirm = c3 < ema;

   return bullish1 && bullish2 &&
          bearish3 && breakout && emaConfirm;
}

//+------------------------------------------------------------------+
//| BUY execution                                                    |
//+------------------------------------------------------------------+
void OpenBuy()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double entry = tick.ask;

   double sl = NormalizeDouble(
      iLow(_Symbol, PERIOD_M5, 1) -
      StopBufferPips * PipSize(), _Digits);

   double risk = entry - sl;

   if(risk <= 0.0)
      return;

   double tp = NormalizeDouble(
      entry + risk * RiskReward, _Digits);

   double lot = CalculateLot(ORDER_TYPE_BUY,
                             entry, sl);

   if(lot <= 0.0)
   {
      Print("BUY skipped: minimum lot exceeds risk budget.");
      return;
   }

   if(trade.Buy(lot, _Symbol, 0.0, sl, tp,
                "Three Candle BUY"))
      Print("BUY order submitted.");
   else
      Print("BUY failed: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| SELL execution                                                   |
//+------------------------------------------------------------------+
void OpenSell()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double entry = tick.bid;

   double sl = NormalizeDouble(
      iHigh(_Symbol, PERIOD_M5, 1) +
      StopBufferPips * PipSize(), _Digits);

   double risk = sl - entry;

   if(risk <= 0.0)
      return;

   double tp = NormalizeDouble(
      entry - risk * RiskReward, _Digits);

   double lot = CalculateLot(ORDER_TYPE_SELL,
                             entry, sl);

   if(lot <= 0.0)
   {
      Print("SELL skipped: minimum lot exceeds risk budget.");
      return;
   }

   if(trade.Sell(lot, _Symbol, 0.0, sl, tp,
                 "Three Candle SELL"))
      Print("SELL order submitted.");
   else
      Print("SELL failed: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(_Period != PERIOD_M5)
   {
      Print("Attach EA to a 5-minute chart.");
      return INIT_FAILED;
   }

   if(RiskPercent <= 0.0 ||
      RiskReward <= 0.0 ||
      MaxTrades < 1 ||
      EMAPeriod < 1 ||
      StopBufferPips < 0.0 ||
      MaxSpreadPips < 0.0)
      return INIT_PARAMETERS_INCORRECT;

   emaHandle = iMA(_Symbol, PERIOD_M5,
                   EMAPeriod, 0, MODE_EMA,
                   PRICE_CLOSE);

   if(emaHandle == INVALID_HANDLE)
      return INIT_FAILED;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   Print("Nkateko Scalper v1.0 initialized.");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
}

//+------------------------------------------------------------------+
//| Main trading engine                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   if(Bars(_Symbol, PERIOD_M5) < EMAPeriod + 10)
      return;

   datetime currentBar = iTime(
      _Symbol, PERIOD_M5, 0);

   if(currentBar == 0 || currentBar == lastBarTime)
      return;

   lastBarTime = currentBar;

   if(CountPositions() >= MaxTrades)
      return;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double spread = (tick.ask - tick.bid) / PipSize();

   if(spread > MaxSpreadPips)
   {
      Print("Trade skipped: spread too high.");
      return;
   }

   double emaBuffer[1];

   if(CopyBuffer(emaHandle, 0, 1, 1,
                 emaBuffer) != 1)
      return;

   double ema = emaBuffer[0];

   if(BuySignal(ema))
   {
      OpenBuy();
      return;
   }

   if(SellSignal(ema))
   {
      OpenSell();
      return;
   }
}
//+------------------------------------------------------------------+
