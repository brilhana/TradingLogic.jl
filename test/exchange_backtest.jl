@testset "Exchange responses for backtesting"
  @testset "Software-implemented limit order"
    plim = 150.0
    buyord = TradingLogic.Order("buysome", 10, plim,
                                :buy, :limit, :pending, "aux")
    sellord = TradingLogic.Order("sellsome", 10, plim,
                                 :sell, :limit, :pending, "aux")
    @test TradingLogic.plimitcheck(buyord, 175.0) == false
    @test TradingLogic.query_orderstatus(buyord, 175.0) == :pending
    @test TradingLogic.plimitcheck(buyord, 125.0) == true
    @test TradingLogic.query_orderstatus(buyord, 125.0) == :complete
    @test TradingLogic.plimitcheck(sellord, 175.0) == true
    @test TradingLogic.query_orderstatus(sellord, 175.0) == :complete
    @test TradingLogic.plimitcheck(sellord, 125.0) == false
    @test TradingLogic.query_orderstatus(sellord, 125.0) == :pending
  end
  @testset "Market order and order submission"
    ordid = "markord"
    mord = TradingLogic.Order(ordid, 10, NaN,
                              :buy, :market, :pending, "aux")
    # buy no matter how high
    @test TradingLogic.query_orderstatus(mord, 1e7) == :complete
    # simulated order submission
    @test TradingLogic.submit_ordernew(mord, false) == "FAIL"
    @test TradingLogic.submit_ordernew(mord, true) == ordid
  end
  @testset "Cancel pending limit-order"
    limord = TradingLogic.Order("buysome", 10, 100.0,
                                :buy, :limit, :pending, "aux")
    @test TradingLogic.submit_ordercancel(limord) == true
    # can not cancel non-pending order
    @test TradingLogic.submit_ordercancel(
      TradingLogic.emptyorder()) == false
  end
end
