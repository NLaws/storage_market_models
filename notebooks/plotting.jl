using DataFrames
using Plots.PlotMeasures: mm
using Statistics
using StatsPlots

function _build_outer_legend_panel(labels, colors, mean_colors; show_means::Bool, legendfontsize::Integer, legend_column::Integer)
    legend_plot = plot(
        legend = :topleft,
        framestyle = :none,
        grid = false,
        axis = false,
        ticks = false,
        xlims = (0, 1),
        ylims = (0, 1),
        legendfontsize = legendfontsize,
        legend_column = legend_column,
        left_margin = 2mm,
        right_margin = 10mm,
        top_margin = 2mm,
        bottom_margin = 2mm,
    )

    for i in eachindex(labels)
        scatter!(
            legend_plot,
            [NaN],
            [NaN],
            markershape = :rect,
            markersize = 8,
            markercolor = colors[i],
            markeralpha = 0.45,
            markerstrokecolor = :black,
            markerstrokealpha = 0.8,
            label = labels[i],
        )
    end

    if show_means
        for i in eachindex(labels)
            scatter!(
                legend_plot,
                [NaN],
                [NaN],
                markershape = :circle,
                markersize = 5,
                markercolor = mean_colors[i],
                markerstrokewidth = 0,
                label = "$(labels[i]) mean",
            )
        end
    end

    return legend_plot
end


"""
    plot_results_column_by_time(
        dfs::AbstractVector{<:AbstractDataFrame};
        column::Symbol,
        labels::AbstractVector{<:AbstractString},
        colors = [:steelblue, :seagreen4, :darkorange2],
        mean_colors = [:navy, :seagreen4, :darkorange4],
        offsets = [-0.18, 0.0, 0.18],
        bar_width::Real = 0.14,
        xlabel::AbstractString = "Time",
        ylabel::AbstractString = ...,
        title::AbstractString = ...,
        time_col::Symbol = :time,
        output_path::Union{Nothing, AbstractString} = nothing,
        show_means::Bool = true,
        outliers::Bool = false,
        legend = :topright,
        outer_legend::Bool = false,
        outer_legend_fraction::Real = 0.30,
        legendfontsize::Integer = 9,
        legend_column::Integer = 1,
        size::Tuple{<:Integer, <:Integer} = (1000, 600),
    )

Create a boxplot by time for any numeric result column across one or more experiment dataframes.
All dataframes must contain `time_col` and `column`.
"""
function plot_results_column_by_time(
    dfs::AbstractVector{<:AbstractDataFrame};
    column::Symbol,
    labels::AbstractVector{<:AbstractString},
    colors = [:steelblue, :seagreen4, :darkorange2],
    mean_colors = [:navy, :seagreen4, :darkorange4],
    offsets = [-0.18, 0.0, 0.18],
    bar_width::Real = 0.14,
    xlabel::AbstractString = "Time",
    ylabel::AbstractString = string(column),
    title::AbstractString = "$(uppercasefirst(String(column))) by Time",
    time_col::Symbol = :time,
    output_path::Union{Nothing, AbstractString} = nothing,
    show_means::Bool = true,
    outliers::Bool = false,
    legend = :topright,
    outer_legend::Bool = false,
    outer_legend_fraction::Real = 0.30,
    legendfontsize::Integer = 9,
    legend_column::Integer = 1,
    size::Tuple{<:Integer, <:Integer} = (800, 600),
)
    isempty(dfs) && throw(ArgumentError("`dfs` must contain at least one dataframe."))
    length(dfs) == length(labels) || throw(ArgumentError("`dfs` and `labels` must have the same length."))
    length(dfs) == length(colors) || throw(ArgumentError("`dfs` and `colors` must have the same length."))
    length(dfs) == length(mean_colors) || throw(ArgumentError("`dfs` and `mean_colors` must have the same length."))
    length(dfs) == length(offsets) || throw(ArgumentError("`dfs` and `offsets` must have the same length."))
    0 < outer_legend_fraction < 1 || throw(ArgumentError("`outer_legend_fraction` must be between 0 and 1."))

    df_names = Symbol.(names(dfs[1]))

    for (i, df) in pairs(dfs)
        df_names = Symbol.(names(df))
        time_col in df_names || throw(ArgumentError("Dataframe $i is missing column `$(time_col)`."))
        column in df_names || throw(ArgumentError("Dataframe $i is missing column `$(column)`."))
    end

    all_values = reduce(vcat, [collect(skipmissing(df[!, column])) for df in dfs])
    isempty(all_values) && throw(ArgumentError("Column `$(column)` has no values to plot."))

    y_min = minimum(all_values)
    y_max = maximum(all_values)
    span = y_max - y_min
    pad = iszero(span) ? max(abs(y_max) * 0.05, 1.0) : 0.05 * span
    shared_ylims = (y_min - pad, y_max + pad)

    xtick_values = sort(unique(dfs[1][!, time_col]))

    x_positions = [df[!, time_col] .+ offset for (df, offset) in zip(dfs, offsets)]

    p = boxplot(
        x_positions[1],
        dfs[1][!, column],
        color = colors[1],
        fillalpha = 0.45,
        linealpha = 0.8,
        outliers = outliers,
        label = labels[1],
        bar_width = bar_width,
        xlabel = xlabel,
        ylabel = ylabel,
        title = title,
        xticks = (xtick_values, string.(xtick_values)),
        ylims = shared_ylims,
        legend = outer_legend ? false : legend,
        legendfontsize = legendfontsize,
        legend_column = legend_column,
        size = size,
        left_margin = 8mm,
        right_margin = outer_legend ? 4mm : 8mm,
        top_margin = 4mm,
        bottom_margin = 8mm,
    )

    for i in 2:length(dfs)
        boxplot!(
            p,
            x_positions[i],
            dfs[i][!, column],
            color = colors[i],
            fillalpha = 0.45,
            linealpha = 0.8,
            outliers = outliers,
            bar_width = bar_width,
            label = labels[i],
        )
    end

    if show_means
        for i in eachindex(dfs)
            mean_by_time = combine(groupby(dfs[i], time_col), column => mean => :mean_value)
            sort!(mean_by_time, time_col)

            scatter!(
                p,
                mean_by_time[!, time_col] .+ offsets[i],
                mean_by_time.mean_value,
                color = mean_colors[i],
                markersize = 5,
                markerstrokewidth = 0,
                label = "$(labels[i]) mean",
            )
        end
    end

    if outer_legend
        legend_plot = _build_outer_legend_panel(
            labels,
            colors,
            mean_colors;
            show_means = show_means,
            legendfontsize = legendfontsize,
            legend_column = legend_column,
        )
        plot_with_legend = plot(
            p,
            legend_plot,
            layout = grid(1, 2, widths = [1 - outer_legend_fraction, outer_legend_fraction]),
            size = (
                ceil(Int, size[1] / (1 - outer_legend_fraction)),
                size[2],
            ),
            margin = 0mm,
        )
        if !isnothing(output_path)
            savefig(plot_with_legend, output_path)
        end
        return plot_with_legend
    end

    if !isnothing(output_path)
        savefig(p, output_path)
    end

    return p
end


"""
    plot_charge_by_time(dfs; kwargs...)

Convenience wrapper around `plot_results_column_by_time` for the `:charge` column.
"""
function plot_charge_by_time(dfs::AbstractVector{<:AbstractDataFrame}; kwargs...)
    return plot_results_column_by_time(
        dfs;
        column = :charge,
        ylabel = "Charge",
        title = "Battery Charge by Time",
        kwargs...,
    )
end
