
```sh
julia1.11 --project=. run_me.jl
```

Run the unit tests from this directory:

```sh
julia --project=. test/runtests.jl
```

The experiment base case is `inputs_base::BIMInputs`. Network demand, generator limits,
and storage limits come from `src/networks/base-single-ess.yaml`; price and cost
vectors come from `src/inputs.jl`. Use `replace_inputs(inputs_base; b = 60.0)` to
change the terminal SOC bid without mutating the base case.

Generate the plotting inputs in parallel from this directory:

```sh
julia --project=. --threads=1 -p 6 run_experiments.jl
```

Like `run_me.jl`, `run_experiments.jl` runs `run_base()` by default and exposes
four commented calls for noisy offers and uniform errors, each with or without
perfect foresight. Uncomment the desired calls to run experiments. The experiment
functions accept `n_samples` (10,000 by default; use 100 for a quick run).
The `run_noisy_offer_sweep` and `run_plot_experiments` helpers remain available
for per-b sweeps and generating all notebook inputs, respectively.
`-p 6` starts six worker
processes, and samples are distributed across those workers.

Results are written to `outputs/bim`. Once the selected runs finish, restart the
Julia kernel and run `notebooks/plot_experiments.ipynb` to load the CSVs and save
plots in `figures/bim`. Running the whole notebook requires all experiment CSVs;
individual runs refresh only their corresponding files.

The experiment runners use `build_bim_single_bid` and `build_bim_multi_bid` and
accept a `network_file_path` keyword. The existing CSV layout supports one battery
on a copper plate with generators named `thermal` and `renewable`. BIM multi-bid
excludes degradation costs from its objective and uses binary operating modes to
prevent simultaneous charging and discharging. Prices come from an LP re-solve
with those modes fixed at their optimal values. Reported ESS surplus still
subtracts degradation costs for comparison with the single-bid reference. The old `Inputs` base case remains available
as `legacy_inputs_base` for `check_duals.jl` and the original model builders.

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
