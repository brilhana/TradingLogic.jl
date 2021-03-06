rel(path::AbstractString) = joinpath(splitdir(@__FILE__)[1], path)

@testset "OHLC backtest with timearray input"
  # using quantstrat goldencross test
  #  details in teststrategy_goldencross.jl
  ohlc_BA = TimeSeries.readtimearray(
    rel("quantstrat/goldencross/data/OHLC_BA_2.csv"))
  targetfun = TradingLogic.goldencrosstarget
  mafast = 50; maslow = 200; targetqty = 100
  date_final = Date(2012,8,31)
  ohlc_ta = ohlc_BA[Date(1961,12,31):date_final]
  ohlc_inds = @compat Dict{Symbol,Int64}()
  ohlc_inds[:open] = 1; ohlc_inds[:close] = 4

  # quantstrat/goldencross/results_summary.txt
  pnlnet_ref = 2211.0 # Net.Trading.PL
  ddownmax_ref = 17374.0 # Max.Drawdown

  # backtest settings
  position_initial = 0
  pfill = :open

  @testset "Final performance and transactions blotter"
    pnlfin, ddownmax, blotter = TradingLogic.runbacktest(
      ohlc_ta, ohlc_inds, nothing, "", pfill, position_initial,
      targetfun, targetqty, mafast, maslow)
    #TradingLogic.printblotter(STDOUT, blotter)
    @test pnlfin == roughly(pnlnet_ref)
    @test ddownmax == roughly(ddownmax_ref)

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

    # verify blotter: transaction matching
    vt, perfm = TradingLogic.tradeperf(blotter, [:DDown])
    @test length(perfm[:Qty]) == length(txnsdf[:datestr])
    @test Date(vt) == vdate
    @test perfm[:Qty] == vqty
    @test perfm[:FillPrice] == roughly(vprc)
  end

  @testset "Output file content"
    fileout = rel("backtest_out.csv")
    dtformat_out = "yyyy-mm-ddTHH:MM:SS"

    pnlfin, ddownmax, blotter = TradingLogic.runbacktest(
      ohlc_ta, ohlc_inds, fileout, dtformat_out,
      pfill, position_initial,
      targetfun, targetqty, mafast, maslow)
    @test pnlfin == roughly(pnlnet_ref)
    @test ddownmax == roughly(ddownmax_ref)

    # output file as timearray
    taf = TimeSeries.readtimearray(fileout,
                                   format=dtformat_out)
    run(`rm $fileout`)
    @test length(taf) == length(ohlc_ta)
    @test taf.timestamp == ohlc_ta.timestamp
    @test taf.colnames == [ohlc_ta.colnames; "CumPnL"; "DDown"]
    @test taf.values[:,1:end-2] == roughly(ohlc_ta.values)
    @test taf["CumPnL"].values[1] == roughly(0.0)
    @test taf["DDown"].values[1] == roughly(0.0)
    @test maximum(abs(taf["DDown"].values)) == roughly(ddownmax_ref)
  end

  @testset "Latest timestep position and targets"
    # final step: non-zero position, no changes targeted
    itfin = findfirst(ohlc_ta.timestamp .== Dates.Date(1967,02,23))
    blotter, posact, targ = TradingLogic.runbacktesttarg(
      ohlc_ta[1:itfin], ohlc_inds, nothing, "", pfill, position_initial,
      targetfun, targetqty, mafast, maslow)
    #TradingLogic.printblotter(STDOUT, blotter)
    @test length(blotter) == 3
    @test posact == 100
    @test targ[1] == 0

    # final step: non-zero position, exit targeted
    # if continued, exit transaction fills on 1967-10-27
    itfin = findfirst(ohlc_ta.timestamp .== Dates.Date(1967,10,26))
    blotter, posact, targ = TradingLogic.runbacktesttarg(
      ohlc_ta[1:itfin], ohlc_inds, nothing, "", pfill, position_initial,
      targetfun, targetqty, mafast, maslow)
    #TradingLogic.printblotter(STDOUT, blotter)
    @test length(blotter) == 3
    @test posact == 100
    @test targ[1] == -100
    # if continued, exit transaction fills on 1967-10-27:
    # verify that, i.e. no double-action next step
    #  to be consistent with orderhandling!
    posnew = posact + targ[1]
    blotter, posact, targ = TradingLogic.runbacktesttarg(
      ohlc_ta[1:itfin+1], ohlc_inds, nothing, "", pfill, position_initial,
      targetfun, targetqty, mafast, maslow)
    @test posnew == posact
    @test targ[1] == 0 # otherwise double position change happens at this step
    posnew = posact + targ[1]
    blotter, posact, targ = TradingLogic.runbacktesttarg(
      ohlc_ta[1:itfin+2], ohlc_inds, nothing, "", pfill, position_initial,
      targetfun, targetqty, mafast, maslow)
    @test posnew == posact
    @test targ[1] == 0

    # final step: zero position, no changes targeted
    itfin = findfirst(ohlc_ta.timestamp .== Dates.Date(1967,10,30))
    blotter, posact, targ = TradingLogic.runbacktesttarg(
      ohlc_ta[1:itfin], ohlc_inds, nothing, "", pfill, position_initial,
      targetfun, targetqty, mafast, maslow)
    #TradingLogic.printblotter(STDOUT, blotter)
    @test length(blotter) == 4
    @test posact == 0
    @test targ[1] == 0
  end
end
