using TradingLogic
using Reactive

@testset "Working with signals"
  @testset "Change detection"
    s_inp = Reactive.Signal(5)
    s_chg = TradingLogic.schange(s_inp)
    push!(s_inp, 5)
    @test s_chg.value == false
    push!(s_inp, 8)
    @test s_chg.value == true
    push!(s_inp, 8)
    @test s_chg.value == false
  end
  @testset "Buffering signal history and SMA calculation"
    # simple vector test case
    nsma = 10
    vval = rand(100)
    vsma = fill(NaN, 100)
    [vsma[i] = mean(vval[(i-nsma+1):i]) for i = 10:100]

    s_inp = Reactive.Signal(vval[1])
    s_sma = Reactive.map(mean, Reactive.foldp(
                            TradingLogic.sighistbuffer!,
                            TradingLogic.initbuff(nsma, s_inp.value),
                            s_inp))
    vsma_sig = Array(Float64, 100)
    vsma_sig[1] = s_sma.value
    for i = 2:100
      push!(s_inp, vval[i])
      vsma_sig[i] = s_sma.value
    end
    @test all(isnan(vsma_sig[1:9])) == true
    @test vsma_sig[10:100] == roughly(vsma[10:100])
  end
end
