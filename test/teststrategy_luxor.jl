@testset "Luxor trading logic"
  @testset "Market state"
    fm = TradingLogic.luxormktstate
    @test fm(120.0, 50.0) == :trendup
    @test fm(20.0, 50.0) == :trenddown
    @test fm(20.0, 20.0) == :undefined
    @test fm(NaN, 20.0) == :undefined
    @test fm(20.0, NaN) == :undefined
    @test fm(NaN, NaN) == :undefined
  end
  @testset "Target position"
    tq = 100
    ft(mkt, posnow) = TradingLogic.luxorposlogic(
      mkt, 155.0, 150.0, 10.0, tq, [posnow])
    stlim = Array(Float64, 0)

    # enter long
    @test ft(:trendup, 0) == (tq, [165.0, 155.0])
    # enter long partial fill
    p = round(Int64, tq/2)
    @test ft(:trendup, p) == (tq - p, [165.0, 155.0])

    # enter short
    @test ft(:trenddown, 0) == (-tq, [140.0, 150.0])
    # enter short partial fill
    p = -round(Int64, tq/2)
    @test ft(:trenddown, p) == (-abs(tq-p), [140.0, 150.0])

    # hold position in line with the market state
    @test ft(:trendup, tq) == (0, stlim)
    @test ft(:trenddown, -tq) == (0, stlim)

    # exit long position
    @test ft(:trenddown, tq) == (-tq, stlim)
    p = round(Int64, tq/2)
    @test ft(:trenddown, p) == (-p, stlim)

    # exit short position
    @test ft(:trendup, -tq) == (tq, stlim)
    p = -round(Int64, tq/2)
    @test ft(:trendup, p) == (abs(p), stlim)

    # undefined: wait
    @test ft(:undefined, 0) == (0, stlim)
    @test ft(:undefined, -tq) == (0, stlim)
    @test ft(:undefined, tq) == (0, stlim)
  end
end

@testset "Luxor strategy backtesting"
  @testset "GBPUSD vs. quantstrat"
    mafast = 10
    maslow = 40
    targetqty = 100
    pthresh = 10.0

    ### TODO change data input
    s_ohlc = Reactive.Signal((Dates.DateTime(ohlc.timestamp[1]),
                              vec(ohlc.values[1,:])))
    ohlc_inds = Dict{Symbol,Int64}()
    ohlc_inds[:open] = 1
    ohlc_inds[:high] = 2
    ohlc_inds[:low] = 3
    ohlc_inds[:close] = 4

    # backtest at next-open price
    # quantstrat fills tracsactions at next open on enter-signal
    s_pnow = Reactive.map(s -> s[2][ohlc_inds[:open]], s_ohlc, typ=Float64)
    blotter = TradingLogic.emptyblotter()

    s_status = TradingLogic.runtrading!(
      blotter, true, s_ohlc, ohlc_inds, s_pnow, 0,
      TradingLogic.luxortarget, mafast, maslow, pthresh, targetqty)

    s_perf = TradingLogic.tradeperfcurr(s_status)

    for i = 2:length(ohlc)
      push!(s_ohlc, (Dates.DateTime(ohlc.timestamp[i]),
                     vec(ohlc.values[i,:])))
    end

    TradingLogic.printblotter(STDOUT, blotter)


    metr = [:DDown]
    vt, perfm = TradingLogic.tradeperf(blotter, metr)
    println(vt)
    println(perfm)

    ### TODO
    @pending 0 == 1
  end
end
