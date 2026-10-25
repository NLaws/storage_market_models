Run the tests from the `code` directory:

```sh
julia --project=. test/runtests.jl
```

Run the two-battery copper-plate experiment and generate its single-bid comparison:

```sh
julia --project=. --threads=1 -p 6 run_experiments.jl
```

Edit the function calls at the bottom of `run_experiments.jl` to choose inputs,
network, `n_samples`, `error_range`, `seed`, and `b`. Set `b_values` in the
`run_single_bid` call to choose the comparison terminal SOC bid(s).
The selected inputs and network default to the two-battery scenario.

The `bid_perfect_foresight` loop uses `(false, true)` to generate both runs with
the same errors. Change it to `(false,)` or `(true,)` to run only one mode.
Use `n_samples = 100` for a quick run. `-p 6` starts six sample workers.
The single-bid comparison runs after the multibid experiments.

`inputs_multiple_ess` in `src/inputs.jl` supplies independent bid/cost vectors for
`battery1` and `battery2` in `src/networks/copper-plate-multiple-ess.yaml`. Edit
those dictionaries to vary bids or degradation costs by battery. `inputs_base`
uses `src/networks/base-single-ess.yaml`. Both scenarios use six four-hour periods.
`replace_inputs(inputs; b = 60.0)` copies inputs while changing terminal SOC bids.

Every sample, battery, and time interval receives its own independent
`Uniform(-error_range, error_range)` draw. Discharge offers equal the single-bid
reference clearing price plus that error, clamped at zero. Charging bids remain
as configured unless buy foresight is enabled, which sets each battery's bids to
zero wherever its own reference charging dispatch is positive.

Results go to `outputs/bim`, with scenario, bids, sample count, and error range in
filenames. Repeating those settings overwrites those files (including when only
the seed changes). Each CSV has one row per sample/battery/time. `charge`,
`discharge`, `soc`, `noise`, `ess_offer`, `ess_bid`, `battery_surplus`, and
`battery_profit` describe that battery. `ess_surplus` and `ess_profit` describe
the fleet; `price`, `demand`, `thermal`, `renewable`, and system monetary metrics
repeat across batteries. Count system metrics once per sample, rather than
summing them over battery rows. Single-bid files use the same layout plus `b`.

In `notebooks/plot_experiments.ipynb`, set the configuration cell to the same
`scenario`, `n_samples`, `error_range`, and `b`. The notebook automatically discovers
all available `singlebid_results_<scenario>_b*.csv` files, sorts terminal bids
numerically, and plots every reference separately with a labeled color. Set `battery_view =
nothing` for fleet dispatch/SOC/surplus or `"battery1"` / `"battery2"` to inspect one
battery. Set `plot_column` in the diagnostic plot cell to `:ess_offer`, `:noise`, `:soc`,
`:discharge`, or another numeric interval column. Prices and costs always describe the system. Fleet bid/offer/noise
columns are arithmetic means; raw battery rows remain available in
`multi_uniform_battery_df`. The notebook automatically finds the optional
buy-foresight file and writes figures under a configuration-specific directory
in `figures/bim`. Restart the kernel and run from the top after changing settings.
Legacy single-battery CSVs can still be loaded with `battery_view = nothing`.

The local network loader preserves all batteries sharing a bus, working around
the installed CommonOPF loader's replacement of repeated battery attributes.

The runners support copper-plate networks with generators named `thermal` and
`renewable`. BIM multibid excludes degradation costs from its objective and uses
binary modes to prevent simultaneous charging/discharging. Prices are LP duals
after fixing optimal modes. Reported surplus subtracts degradation costs. The
legacy `Inputs` case remains available as `legacy_inputs_base` for `check_duals.jl`.

# Definitions
- $x_t$ thermal dispatch
- $c_x$ thermal offers
- $r_t$ renewable dispatch
- $c_r$ renewable offers
- $s_t$ state of charge
- $p_t$ charge
- $g_t$ discharge
- $b_T$ storage bid for energy in last time interval $T$
- $\overline{\overline{s_T}} = \gamma^T s_0$ SOC at the end of the DA
horizon if the ESS were to neither charge nor discharge during the horizon
- $\eta^{\text{ch}}$ charge efficiency
- $\eta^{\text{di}}$ discharge efficiency
- $\gamma$ per interval self-discharge
- $\epsilon$ charge degradation cost
- $\zeta$ discharge degradation cost

# End-interval bid model
```math
\begin{aligned}
\min  & \quad \boldsymbol c_x^\intercal \boldsymbol x + \boldsymbol c_r^\intercal \boldsymbol r 
\\ & \quad 
+ \epsilon \sum_{t \in \mathcal T} p_t 
+ \zeta \sum_{t \in \mathcal T} g_t
- b_T \left( s_T - \overline{\overline{s_T}}\right)
\\
\text{s.t.} &\quad x_t + g_t + r_t - p_t = d_t  &\forall t \in \mathcal{T}
\\
&\quad \ \underline{x} \leq x_t \leq \overline{x}  &\forall t \in \mathcal{T}
\\
&\quad \ \underline{r} \leq r_t \leq \overline{r}  &\forall t \in \mathcal{T}
\\
&\quad \ 0 \leq p_t \leq \overline{p}  &\forall t \in \mathcal{T}
\\
&\quad \ 0 \leq g_t \leq \overline{g}  &\forall t \in \mathcal{T}
\\
&\quad \ p_t \perp g_t                   &\forall t \in \mathcal{T}
\\
&\quad \ s_t = \Delta T \eta^{\text{ch}} p_t - \Delta T  g_t / \eta^{\text{di}}+ \gamma s_{t-1}
&\forall t \in \mathcal{T}
\\
&\quad \ \underline{s} \leq s_0 \leq \overline{s}
\\
&\quad \ \gamma s_{t-1} + \Delta T \eta^{\text{ch}} p_t \leq \overline{s}
&\forall t \in \mathcal{T}
\\
&\quad \ \gamma s_{t-1} - \Delta T  g_t / \eta^{\text{di}} \geq \underline{s}
&\forall t \in \mathcal{T}
\end{aligned}
```

# Multi-interval bids model
```math
\begin{aligned}
\min  & \quad \boldsymbol c_x^\intercal \boldsymbol x + \boldsymbol c_r^\intercal \boldsymbol r 
    + \boldsymbol c_g^\intercal \boldsymbol g - \boldsymbol c_p^\intercal \boldsymbol p 
\\
\text{s.t.} &\quad x_t + g_t + r_t - p_t = d_t  &\forall t \in \mathcal{T}
\\
&\quad \ \underline{x} \leq x_t \leq \overline{x}  &\forall t \in \mathcal{T}
\\
&\quad \ \underline{r} \leq r_t \leq \overline{r}  &\forall t \in \mathcal{T}
\\
&\quad \ 0 \leq p_t \leq \overline{p}  &\forall t \in \mathcal{T}
\\
&\quad \ 0 \leq g_t \leq \overline{g}  &\forall t \in \mathcal{T}
\\
&\quad \ p_t \perp g_t                   &\forall t \in \mathcal{T}
\\
&\quad \ \underline{s} \leq s_t \leq \overline{s}   &\forall t \in \mathcal{T}
\\
&\quad \ s_t = s_{t-1} + \Delta T \eta p_t - \Delta T g_t + \text{A.S terms}
&\forall t \in \mathcal{T}
\end{aligned}
```

# TODO
- time independent model
    - with varying ESS offers/bids (use `b` in time-coupled model?)
- show results in notebook? (so they are in the repo)
    - or add a docs page that fills via running the code
- forecast errors: random noise on baseline prices
- scenarios with ESS as price-maker and taker
