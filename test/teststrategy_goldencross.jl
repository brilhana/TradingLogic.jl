@testset "Goldencross trading logic"
  @testset "Market state"
    fm = TradingLogic.goldencrossmktstate
    @test fm(120.0, 50.0) == :trendup
    @test fm(20.0, 50.0) == :trenddown
    @test fm(20.0, 20.0) == :undefined
    @test fm(NaN, 20.0) == :undefined
    @test fm(20.0, NaN) == :undefined
    @test fm(NaN, NaN) == :undefined
  end
  @testset "Target position"
    tq = 100
    ft(mkt, posnow) = TradingLogic.goldencrossposlogic(
      mkt, tq, [posnow])
    stlim = Array(Float64, 0)

    # up, zero position
    @test ft(:trendup, 0) == (tq, stlim)
    # up, position less than target (e.g. partial fill)
    p = round(Int64, tq/2)
    @test ft(:trendup, p) == (tq - p, stlim)

    # down: sell
    @test ft(:trenddown, tq) == (-tq, stlim)
    @test ft(:trenddown, p) == (-p, stlim)
    # down: nothing left to sell
    @test ft(:trenddown, 0) == (0, stlim)

    # hold position in line with the market state
    @test ft(:trendup, tq) == (0, stlim)

    # undefined: wait
    @test ft(:undefined, tq) == (0, stlim)

    # negative position: should not happen, close it
    @test ft(:trendup, -5) == (5, stlim)
    @test ft(:trenddown, -5) == (5, stlim)
    @test ft(:undefined, -5) == (5, stlim)
  end
end

@testset "Goldencross strategy backtesting"
  @testset "Boeing stock over 50 years vs. quantstrat"
    # quantstrat input: OHLC data
    ohlc_BA = TimeSeries.readtimearray(
      rel("quantstrat/goldencross/data/OHLC_BA_2.csv"))
    # parameters should match
    #  test/quantstrat/goldencross/quantstrat_goldencross.R
    mafast = 50
    maslow = 200
    targetqty = 100
    # restrict between start and end dates
    #println(ohlc_BA)
    ##ohlc_test = ohlc_BA[Date(1961,12,31):Date(2010,1,1)]
    # in reality: quantstrat transactions are present
    # past the end date
    date_final = Date(2012,8,31)
    ohlc_test = ohlc_BA[Date(1961,12,31):date_final]
    #println(ohlc_test)
    # NOTE: excluding period around 2012-09-06 where
    # quantstrat behavior differs from TradingLogic by design

    # quantstrat output: transactions
    txnsdf = DataFrames.readtable(
      rel("quantstrat/goldencross/transactions.csv"),
      header = true,
      names = [:datestr, :qty, :prc, :fees, :val, :avgcost, :pl],
      eltypes = [String, Int64, Float64, Float64,
                 Float64, Float64, Float64])[2:end,:]
    # vectors to verify
    vqty = convert(Array, txnsdf[:qty])
    vprc = convert(Array, txnsdf[:prc])
    vpnlcum = cumsum(convert(Array, txnsdf[:pl]))
    # NOTE: quantstrat records transaction times when
    #  signal is fired not when open fill-price is taken
    # adjusting for that
    vdate = Date(DateTime(convert(Array, txnsdf[:datestr]),
                          "yyyy-mm-dd HH:MM:SS"))
    oneday = Day(1)
    for i = 1:length(vdate)
      vdate[i] = vdate[i] + oneday
    end

    s_ohlc = Reactive.Signal((Dates.DateTime(ohlc_test.timestamp[1]),
                              vec(ohlc_test.values[1,:])))
    ohlc_inds = Dict{Symbol,Int64}()
    ohlc_inds[:open] = 1
    ohlc_inds[:close] = 4

    # backtest at next-open price
    # quantstrat fills tracsactions at next open on enter-signal
    s_pnow = Reactive.map(s -> s[2][ohlc_inds[:open]], s_ohlc, typ=Float64)
    blotter = TradingLogic.emptyblotter()

    s_status = TradingLogic.runtrading!(
      blotter, true, s_ohlc, ohlc_inds, s_pnow, 0,
      TradingLogic.goldencrosstarget, targetqty, mafast, maslow)

    s_perf = TradingLogic.tradeperfcurr(s_status)

    for i = 2:length(ohlc_test)
      push!(s_ohlc, (Dates.DateTime(ohlc_test.timestamp[i]),
                     vec(ohlc_test.values[i,:])))
      #println(s_perf.value)
    end
    # no errors
    @test s_status.value[1] == true

    #TradingLogic.printblotter(STDOUT, blotter)
    metr = [:DDown]
    vt, perfm = TradingLogic.tradeperf(blotter, metr)
    #println(vt)
    #println(perfm[:PnL])

    # transaction matching
    @test length(perfm[:Qty]) == length(txnsdf[:datestr])
    @test Date(vt) == vdate
    @test perfm[:Qty] == vqty
    @test perfm[:FillPrice] == roughly(vprc)

    # profit loss over time
    @test perfm[:PnL] == roughly(vpnlcum)
    #println(perfm)

    # quantstrat/goldencross/results_summary.txt
    pnlnet = 2211.0 # Net.Trading.PL
    ddownmax = 17374.0 # Max.Drawdown

    # not final PnL without exit yet
    @test TradingLogic.tradepnlfinal(blotter) - pnlnet > 10.0 == true
    # but final PnL if exit price is given: last timestep close price
    pfinal = s_ohlc.value[2][ohlc_inds[:close]]
    @test TradingLogic.tradepnlfinal(blotter, pfinal) == roughly(pnlnet)

    # add exit to blotter for cumulative statistics at the end date
    blotter[DateTime(date_final)] = (-sum(perfm[:Qty]), pfinal)

    @test TradingLogic.tradepnlfinal(blotter) == roughly(pnlnet)
    # perfm[:DDown] does not have the true max. drawdown
    # as it is only blotter timesteps based;
    # use performance metrics signal for that
    @test s_perf.value[2] == roughly(ddownmax)
  end
end
