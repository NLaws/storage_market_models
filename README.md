
```sh
julia1.11 --project=. run_me.jl
```

# Definitions
- $x_t$ thermal dispatch
- $c_x$ thermal offers
- $r_t$ renewable dispatch
- $c_r$ renewable offers
- $s_t$ state of charge
- $p_t$ charge
- $g_t$ discharge
- $b$ storage bid for energy in last time interval $T$
- $\overline{\overline{s_T}} = \gamma^T s_0$ SOC at the end of the DA
horizon if the ESS were to neither charge nor discharge during the horizon
- $\alpha$ charge efficiency
- $\beta$ discharge efficiency
- $\gamma$ per interval self-discharge
- $\epsilon$ charge degradation cost
- $\zeta$ discharge degradation cost

# Time-coupled model
```math
\begin{aligned}
\min  & \quad \boldsymbol c_x^\intercal \boldsymbol x + \boldsymbol c_r^\intercal \boldsymbol r 
\\ & \quad 
+ \epsilon \sum_{t \in \mathcal T} p_t 
+ \zeta \sum_{t \in \mathcal T} g_t
- b \left( s_T - \overline{\overline{s_T}}\right)
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
&\quad \ s_t = \Delta T \alpha p_t - \Delta T \beta g_t + \gamma s_{t-1}
&\forall t \in \mathcal{T}
\\
&\quad \ \underline{s} \leq s_0 \leq \overline{s}
\\
&\quad \ \gamma s_{t-1} + \Delta T \alpha p_t \leq \overline{s}
&\forall t \in \mathcal{T}
\\
&\quad \ \gamma s_{t-1} - \Delta T \beta g_t \geq \underline{s}
&\forall t \in \mathcal{T}
\end{aligned}
```

# Time-independent model
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
&\quad \ \underline{s} \leq s_t \leq \overline{s}
\end{aligned}
```

# TODO
- time independent model
    - with varying ESS offers/bids (use `b` in time-coupled model?)
- show results in notebook? (so they are in the repo)
    - or add a docs page that fills via running the code