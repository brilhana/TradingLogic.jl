__precompile__(true)

using Dates, Reactive, Match, TimeSeries, Compat

module TradingLogic

export runtrading!, runbacktest, runbacktesttarg
export emptyblotter, printblotter, writeblotter
export tradeperfcurr, tradeperf, tradepnlfinal, vtradespnl, perf_prom

# general components
include("sigutils.jl")
include("types.jl")
include("errorhandl.jl")
include("exchange.jl")
include("orderhandl.jl")
include("performance.jl")

# specific trading strategy examples
include("strategies/goldencross.jl")
include("strategies/luxor.jl")

"Event-driven backtesting / live trading."
:runtrading!

"""
Backtesting or real-time order submission with status output.

Input:

- `blotter` (could be initially empty) to write transactions to,
as an associative collection DateTime => (Qty::Int64, FillPrice::Float64)`;
- `backtest` is `Bool`, live trading performed if `false`;
- `s_ohlc` is tuple-valued `(DateTime, Vector-ohlc)` signal;
- `ohlc_inds` provides index correspondence in Vector-ohlc;
- `s_pnow` is instantaneous price signal;
- `position_initial` corresponds to the first timestep;
- `targetfun` is the trading strategy function generating
`(poschg::Int64, Vector[limitprice, stopprice]` signal;
- additional arguments `...` to be passed to `targetfun`: these would
most commonly be trading strategy parameters.

In-place modifies `blotter` (adds transactions to it).

Returns tuple-signal with:

* the overall status of the trading system (false if problems are detected);
* current cumulative profit/loss since the signals were initiated (i.e. since
the beginning of the trading session).

See `orderhandling!` for the PnL details.
"""
function runtrading!(blotter::Blotter,
                     backtest::Bool,
                     s_ohlc::Signal{OHLC},
                     ohlc_inds::Dict{Symbol,Int64},
                     s_pnow::Signal{Float64},
                     position_initial::Int64,
                     targetfun::Function, strategy_args...)
  # set initial position in a mutable object
  # NOTE: using closures to deal with a cyclic part of the signal graph
  # (for the actual position and current order updates) since
  # concurrent reactive programming is outside the scope of Reactive.jl
  position_actual_mut = [position_initial]

  # target signal: strategy-specific
  ##s_target = apply(targetfun, tuple(s_ohlc, ohlc_inds,
  ##                                  position_actual_mut, strategy_args...))
  s_target = targetfun(tuple(s_ohlc, ohlc_inds,
                                    position_actual_mut, strategy_args...)...)

  # current time signal from OHLC timestamp
  s_tnow = Reactive.map(s -> s[1], s_ohlc, typ=DateTime)

  # general order handling part
  order_current = emptyorder()
  s_overallstatus = map(
    (tgt, pnow, tnow) -> orderhandling!(tgt, pnow, tnow,
                                        position_actual_mut,
                                        order_current,
                                        blotter, backtest),
    s_target, s_pnow, s_tnow, typ=@compat(Tuple{Bool,Float64}))
  # error notification
  map(s -> tradesyserror(s[1]), s_overallstatus, typ=Bool)

  return s_overallstatus
end

"""
Backtesting process with final position and targets included in the output.

Input: `backtest = true` enforced. Error notification function is
not called (check the status-output signal tuple).

Return tuple components:

* `s_overallstatus` tuple-signal;
* current position single-element mutable array with `Int64` value;
* current target signal per targeting function output.

This method is useful for feeding current step's targets
to some external code.
"""
function runtrading!(blotter::Blotter,
                     s_ohlc::Signal{OHLC},
                     ohlc_inds::Dict{Symbol,Int64},
                     s_pnow::Signal{Float64},
                     position_initial::Int64,
                     targetfun::Function, strategy_args...)
  backtest = true
  position_actual_mut = [position_initial]

  # target signal: strategy-specific
  ##s_target = apply(targetfun, tuple(s_ohlc, ohlc_inds,
  ##                                  position_actual_mut, strategy_args...))
  s_target = targetfun(tuple(s_ohlc, ohlc_inds,
                                    position_actual_mut, strategy_args...)...)

  # current time signal from OHLC timestamp
  s_tnow = Reactive.map(s -> s[1], s_ohlc, typ=DateTime)

  # general order handling part
  order_current = emptyorder()
  s_overallstatus = map(
    (tgt, pnow, tnow) -> orderhandling!(tgt, pnow, tnow,
                                        position_actual_mut,
                                        order_current,
                                        blotter, backtest),
    s_target, s_pnow, s_tnow, typ=@compat(Tuple{Bool,Float64}))

  return s_overallstatus, position_actual_mut, s_target
end

"""
Backtesting run with OHLC timearray input.
Selected performance metrics and equity curve in the output.

Input:

- `ohlc_ta` timearray with OHLC data along with any other input values
provided at each timestep for the trading strategy use;
- `ohlc_inds` provides index correspondence for `ohlc_ta.colnames`;
**at least** the index of `:close` has to be specified.
- `fileout` filename with path or `nothing` to suppress output at each step;
- `dtformat_out` formats `DateTime` in `fileout`
(use e.g. `""` if not writing the output)
- `pfill` specifies price symbol in `ohlc_inds` to use for filling orders
at next-timestep after placement. Commonly set to open price.
**NOTE**: final performance metrics are using `:close` at the last timestep.
- `position_initial` corresponds to the first timestep;
- `targetfun` is the trading strategy function generating
`(poschg::Int64, Vector[limitprice, stopprice]` signal;
- additional arguments `...` to be passed to `targetfun`: these would
most commonly be trading strategy parameters.

Returns tuple with:

* `Float64` final cumulative profit/loss;
* `Float64` maximum return-based drawdown;
* transaction blotter as an associative collection;
* `Vector{Float64}` equity curve (values for each timestep of `ohlc_ta`).

Make sure to suppress output file when using within
optimization objective function to improve performance.
"""
function runbacktest{M}(ohlc_ta::TimeSeries.TimeArray{Float64,2,M},
                        ohlc_inds::Dict{Symbol,Int64},
                        fileout::Union{Void,AbstractString},
                        dtformat_out,
                        pfill::Symbol,
                        position_initial::Int64,
                        targetfun::Function, strategy_args...)
  # initialize signals
  s_ohlc = Signal((Dates.DateTime(ohlc_ta.timestamp[1]),
                   vec(ohlc_ta.values[1,:])))
  s_pnow = map(s -> s[2][ohlc_inds[pfill]], s_ohlc, typ=Float64)
  blotter = emptyblotter()
  s_status = runtrading!(blotter, true, s_ohlc, ohlc_inds, s_pnow,
                         position_initial, targetfun, strategy_args...)
  s_perf = tradeperfcurr(s_status)

  # core of the backtest run
  vequity = runbacktestcore(ohlc_ta, s_ohlc, s_status, s_perf,
                            fileout, dtformat_out)

  # finalize perf. metrics at the last step close-price
  pfinal = s_ohlc.value[2][ohlc_inds[:close]]
  pnlfin = tradepnlfinal(blotter, pfinal)
  pnlmax = s_perf.value[1] > pnlfin ? s_perf.value[1] : pnlfin
  ddownfin = pnlfin - pnlmax
  ddownmax = s_perf.value[2] > ddownfin ? s_perf.value[2] : ddownfin

  # FinalPnL, MaxDDown, blotter, equity curve
  return pnlfin, ddownmax, blotter, vequity
end

"""
Similar to `runbacktest` but instead of performance metrics,
current position and targets from the latest step are included
in the output.

Input: same as `runbacktest`.

Return tuple components:

* transaction blotter as an associative collection;
* `Int64` position as of the latest timestep;
* `Targ` targeting tuple as of the latest timestep.

This function is useful to run through a recent historical period and
determine the latest timestep actions.
"""
function runbacktesttarg{M}(ohlc_ta::TimeSeries.TimeArray{Float64,2,M},
                            ohlc_inds::Dict{Symbol,Int64},
                            fileout::Union{Void,AbstractString},
                            dtformat_out,
                            pfill::Symbol,
                            position_initial::Int64,
                            targetfun::Function, strategy_args...)
  # initialize signals
  s_ohlc = Signal((Dates.DateTime(ohlc_ta.timestamp[1]),
                   vec(ohlc_ta.values[1,:])))
  nt = length(ohlc_ta)
  s_pnow = map(s -> s[2][ohlc_inds[pfill]], s_ohlc, typ=Float64)
  blotter = emptyblotter()

  # using method with targeting info output
  s_status, pos_act_mut, s_targ = runtrading!(
    blotter, s_ohlc, ohlc_inds, s_pnow, position_initial,
    targetfun, strategy_args...)
  s_perf = tradeperfcurr(s_status)

  # core of the backtest run
  vequity = runbacktestcore(ohlc_ta, s_ohlc, s_status, s_perf,
                            fileout, dtformat_out)

  # blotter, latest position, latest targets
  ##println("timestep")
  ##println(s_ohlc.value[1])
  if haskey(blotter, s_ohlc.value[1])
    # current step had position update;
    # avoid double action, be consistent with orderhandling!:
    # no forther target position change at this step
    newtarg = 0
  else
    newtarg = s_targ.value
  end

  return blotter, pos_act_mut[1], newtarg
end

"Core of the backtest run."
function runbacktestcore{M}(ohlc_ta::TimeSeries.TimeArray{Float64,2,M},
                            s_ohlc::Signal{OHLC},
                            s_status::Signal{@compat(Tuple{Bool, Float64})},
                            s_perf::Signal{@compat(Tuple{Float64, Float64})},
                            fileout::Union{Void,AbstractString},
                            dtformat_out)
  nt = length(ohlc_ta)
  vequity = zeros(nt)

  if fileout == nothing
    writeout = false
  else
    # prepare file to write to at each timestep
    fout = open(fileout, "w")
    separator = ','; quotemark = '"'
    rescols = ["Timestamp"; ohlc_ta.colnames; "CumPnL"; "DDown"]
    printvecstring(fout, rescols, separator, quotemark)
    writeout = true
  end
  for i = 1:nt
    if i > 1
      # first timestep already initialized all the signals
      push!(s_ohlc, (Dates.DateTime(ohlc_ta.timestamp[i]),
                     vec(ohlc_ta.values[i,:])))
    end
    pnlcum = s_status.value[2]
    vequity[i] = pnlcum
    if writeout
      # print current step info: timestamp
      print(fout, quotemark)
      print(fout, Dates.format(s_ohlc.value[1], dtformat_out))
      print(fout, quotemark); print(fout, separator)
      # OHLC timearray columns
      print(fout, join(s_ohlc.value[2], separator))
      print(fout, separator)
      # trading performance
      ddownnow = pnlcum - s_perf.value[1]
      print(fout, pnlcum) #CumPnL
      print(fout, separator)
      print(fout, ddownnow) #DDown
      print(fout, '\n')
    end
  end
  if writeout
    close(fout)
  end

  return vequity
end

end # module
