
```sh
julia1.11 --project=. run_me.jl
```



```math
\begin{aligned}
\min  & \quad \boldsymbol c^\intercal \boldsymbol x 
+ \epsilon \sum_{t \in \mathcal T} p_t 
+ \zeta \sum_{t \in \mathcal T} g_t
+ b \left( s_T - \overline{\overline{s_T}}\right)
\\
\text{s.t.} &\quad \boldsymbol C \boldsymbol x \leq \boldsymbol d
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
&\quad \ \underbar{s} \leq s_0 \leq \overline{s}
\\
&\quad \ \gamma s_{t-1} + \Delta T \alpha p_t \leq \overline{s}
&\forall t \in \mathcal{T}
\\
&\quad \ \gamma s_{t-1} - \Delta T \beta g_t \geq \underbar{s}
&\forall t \in \mathcal{T}
\end{aligned}
```