@testset "Order object methods"
  @testset "Constructor checks"
    @test TradingLogic.Order("error", 10, 150.0,
                             :obscuresym,
                             :market, :complete, "string")
    @test TradingLogic.Order("error", 10, 150.0,
                             :buy, :obscuresym,
                             :complete, "string")
    @test TradingLogic.Order("error", 10, 150.0,
                             :buy, :market,
                             :obscuresym, "string")
  end
  @testset "Get info and modify methods"
    emptord = TradingLogic.emptyorder()
    @test TradingLogic.getorderposchg(emptord) == 0
    @test TradingLogic.ispending(emptord) == false
    emptord.status = :pending
    @test TradingLogic.ispending(emptord) == true
    TradingLogic.setcancelled!(emptord)
    @test TradingLogic.ispending(emptord) == false

    # targeted position change with proper sign
    emptord.side = :qq
    @test TradingLogic.getorderposchg(emptord)
    posord = TradingLogic.Order("pos", 10, 150.0,
                                :buy, :limit, :pending, "aux")
    negord = TradingLogic.Order("neg", 10, 150.0,
                                :sell, :limit, :pending, "aux")
    @test TradingLogic.getorderposchg(posord) > 0 == true
    @test TradingLogic.getorderposchg(negord) < 0 == true
  end
end

@testset "Order handling based on target input"
  @testset "Limit and marker order from target input"
    nostoplim = Array(Float64, 0)
    ord = TradingLogic.emptyorder()
    # should not be calling targ2order! with zero position change
    @test TradingLogic.targ2order!(ord, (0, nostoplim),
                                   "", 0, true) == false
    # stoplimit is not handled by targ2order!
    @test TradingLogic.targ2order!(ord, (10, [1.0, 2.0]),
                                   "", 0, true) == false

    # when no limit price is given: submit market
    ord.ordertype = :limit
    qty = -10
    @test TradingLogic.targ2order!(ord, (qty, nostoplim),
                                   "", 0, true) == true
    @test ord.ordertype == :market
    @test isnan(ord.price) == true
    @test TradingLogic.getorderposchg(ord) == qty
    @test ord.side == :sell
    @test TradingLogic.ispending(ord) == true

    # limit order for submission
    ord = TradingLogic.emptyorder()
    @test ord.ordertype == :market
    @test ord.side == :buy
    @test TradingLogic.ispending(ord) == false
    qty, prc = -50, 100.0
    @test TradingLogic.targ2order!(ord, (qty, [prc]),
                                   "", 150, true) == true
    @test ord.ordertype == :limit
    @test isnan(ord.price) == false
    @test ord.price == roughly(prc)
    @test TradingLogic.getorderposchg(ord) == qty
    @test ord.side == :sell
    @test TradingLogic.ispending(ord) == true
  end

  # orderhandling! input
  tnow() = unix2datetime(time())
  tinit = tnow()
  posactual = [0]
  blotter = TradingLogic.emptyblotter()
  backtest = true

  penter, pexit = 150.0, 110.0
  qty = 10
  shortgain = -(pexit - penter) * qty

  @testset "Order handling: pending order now complete"
    # any target (irrelevant at this step -> evaluated next step)
    targ = (0, Array(Float64, 0))

    # market order was pending
    ord = TradingLogic.Order("neg", qty, NaN, :sell,
                             :market, :pending, "aux")
    @test TradingLogic.ispending(ord) == true
    @test TradingLogic.orderhandling!(
      targ, penter, tinit, posactual, ord,
      blotter, backtest) == (true, 0.0)
    # position updated, no new order generated yet
    # (need to re-evaluate target after position update)
    @test blotter[tinit] == (-qty, penter)
    @test TradingLogic.ispending(ord) == false
    @test posactual[1] == -qty

    # same with limit-order that was pending
    #  and is satisfied at current price
    ord = TradingLogic.Order("pos", qty, 120.0, :buy,
                             :limit, :pending, "aux")
    @test TradingLogic.ispending(ord) == true
    @test TradingLogic.orderhandling!(
      targ, pexit, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # position updated, no new order generated yet
    # (need to re-evaluate target after position update)
    @test TradingLogic.ispending(ord) == false
    @test posactual[1] == 0
    @test length(keys(blotter)) == 2
  end

  @testset "Order handling: no position change targeted"
    targ = (0, Array(Float64, 0))

    # nothing was pending
    ord = TradingLogic.emptyorder()
    @test TradingLogic.ispending(ord) == false
    @test TradingLogic.orderhandling!(
      targ, 100.0, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # now still nothing pending, actual position is the same
    @test TradingLogic.ispending(ord) == false
    @test posactual[1] == 0

    # order was pending that is still pending (limit)
    ord = TradingLogic.Order("pos", 10, 50.0, :buy,
                             :limit, :pending, "aux")
    @test TradingLogic.ispending(ord) == true
    @test TradingLogic.orderhandling!(
      targ, 100.0, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # now pending order gets cancelled
    @test TradingLogic.ispending(ord) == false
    @test ord.status == :cancelled
    # no position updates
    @test posactual[1] == 0
  end

  @testset "Order handling: market buy/sell"
    targ = (10, Array(Float64, 0))

    # nothing was pending
    ord = TradingLogic.emptyorder()
    @test TradingLogic.ispending(ord) == false
    @test TradingLogic.orderhandling!(
      targ, 100.0, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # now pending, actual position still the same
    @test TradingLogic.ispending(ord) == true
    @test ord.ordertype == :market
    @test posactual[1] == 0

    # order was pending that is still pending (limit)
    ord = TradingLogic.Order("pos", 10, 50.0, :buy,
                             :limit, :pending, "aux")
    @test TradingLogic.ispending(ord) == true
    @test TradingLogic.orderhandling!(
      targ, 100.0, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # now market target so cancel pending order
    @test TradingLogic.ispending(ord) == false
    @test ord.status == :cancelled
    # no position updates
    @test posactual[1] == 0
  end

  @testset "Order handling: limit buy/sell"
    targ = (30, [75.0])

    # nothing was pending
    ord = TradingLogic.emptyorder()
    @test TradingLogic.ispending(ord) == false
    @test TradingLogic.orderhandling!(
      targ, 100.0, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # now limit pending, actual position still the same
    @test TradingLogic.ispending(ord) == true
    @test ord.ordertype == :limit
    @test ord.side == :buy
    @test posactual[1] == 0

    # limit order was pending that is still pending
    # in line with the target
    ord = TradingLogic.Order("pos", 30, 75.0, :buy,
                             :limit, :pending, "aux")
    @test TradingLogic.orderhandling!(
      targ, 100.0, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # leave it pending
    @test TradingLogic.ispending(ord) == true
    @test ord.ordertype == :limit
    @test ord.side == :buy
    @test posactual[1] == 0

    # limit order was pending that is still pending
    # position change not in line with the target (value)
    ord = TradingLogic.Order("pos", 25, 75.0, :buy,
                             :limit, :pending, "aux")
    @test TradingLogic.orderhandling!(
      targ, 100.0, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # cancel different order
    @test TradingLogic.ispending(ord) == false
    @test ord.status == :cancelled
    # no position updates
    @test posactual[1] == 0

    # limit order was pending that is still pending
    # position change not in line with the target (side)
    ord = TradingLogic.Order("pos", 30, 75.0, :sell,
                             :limit, :pending, "aux")
    @test TradingLogic.orderhandling!(
      targ, 70.0, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # cancel different order
    @test TradingLogic.ispending(ord) == false
    @test ord.status == :cancelled
    # no position updates
    @test posactual[1] == 0

    # limit order was pending that is still pending
    # limit price not in line with the target
    ord = TradingLogic.Order("pos", 30, 85.0, :buy,
                             :limit, :pending, "aux")
    @test TradingLogic.orderhandling!(
      targ, 100.0, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # cancel different order
    @test TradingLogic.ispending(ord) == false
    @test ord.status == :cancelled
    # no position updates
    @test posactual[1] == 0
  end

  @testset "Order handling: stoplimit to track, buy-side"
    targ = (50, [80.0, 75.0]) #[limitprice, stopprice]

    # nothing was pending
    # stop price not reached
    ord = TradingLogic.emptyorder()
    @test TradingLogic.ispending(ord) == false
    @test TradingLogic.orderhandling!(
      targ, 70.0, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # no change, keep tracking the price
    @test TradingLogic.ispending(ord) == false
    @test posactual[1] == 0

    # nothing was pending
    # stop price reached
    ord = TradingLogic.emptyorder()
    @test TradingLogic.ispending(ord) == false
    @test TradingLogic.orderhandling!(
      targ, 75.1, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # now limit pending, actual position still the same
    @test TradingLogic.ispending(ord) == true
    @test ord.ordertype == :limit
    @test ord.side == :buy
    @test ord.price == roughly(80.0)
    @test posactual[1] == 0

    # limit order was pending that is still pending
    # stop price not reached
    ord = TradingLogic.Order("pos", 30, 65.0, :buy,
                             :limit, :pending, "aux")
    @test TradingLogic.orderhandling!(
      targ, 70.0, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # cancel previous order, keep tracking the price
    @test TradingLogic.ispending(ord) == false
    @test ord.status == :cancelled
    # no position updates
    @test posactual[1] == 0

    # limit order was pending that is still pending
    # stop price reached
    # limit-target and prev. limit-pending can not match
    # (stop < limit for buy, sell symmetrically)
    # here we have (buy) limit_prev < stop < price_curr
    ord = TradingLogic.Order("pos", 50, 70.0, :buy,
                             :limit, :pending, "aux")
    @test TradingLogic.orderhandling!(
      targ, 75.1, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # cancel previous order with different limit-price
    @test TradingLogic.ispending(ord) == false
    @test ord.status == :cancelled
    # no position updates
    @test posactual[1] == 0
  end

  @testset "Order handling: stoplimit to track, sell-side"
    targ = (-50, [60.0, 75.0]) #[limitprice, stopprice]

    # nothing was pending
    # stop price not reached
    ord = TradingLogic.emptyorder()
    @test TradingLogic.ispending(ord) == false
    @test TradingLogic.orderhandling!(
      targ, 80.0, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # no change, keep tracking the price
    @test TradingLogic.ispending(ord) == false
    @test posactual[1] == 0

    # nothing was pending
    # stop price reached
    ord = TradingLogic.emptyorder()
    @test TradingLogic.ispending(ord) == false
    @test TradingLogic.orderhandling!(
      targ, 74.9, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # now limit pending, actual position still the same
    @test TradingLogic.ispending(ord) == true
    @test ord.ordertype == :limit
    @test ord.side == :sell
    @test ord.price == roughly(60.0)
    @test posactual[1] == 0

    # limit order was pending that is still pending
    # stop price not reached
    ord = TradingLogic.Order("neg", 30, 85.0, :sell,
                             :limit, :pending, "aux")
    @test TradingLogic.orderhandling!(
      targ, 80.0, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # cancel previous order, keep tracking the price
    @test TradingLogic.ispending(ord) == false
    @test ord.status == :cancelled
    # no position updates
    @test posactual[1] == 0

    # limit order was pending that is still pending
    # stop price reached
    # limit-target and prev. limit-pending can not match
    # (stop < limit for buy, sell symmetrically)
    # here we have (sell) limit_prev > stop > price_curr
    ord = TradingLogic.Order("neg", 50, 80.0, :sell,
                             :limit, :pending, "aux")
    @test TradingLogic.orderhandling!(
      targ, 74.9, tnow(), posactual, ord,
      blotter, backtest) == (true, shortgain)
    # cancel previous order with different limit-price
    @test TradingLogic.ispending(ord) == false
    @test ord.status == :cancelled
    # no position updates
    @test posactual[1] == 0
  end
  #println(blotter)
end
