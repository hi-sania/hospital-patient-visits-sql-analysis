"""Regenerate the README's executive summary from the synthetic SQL dataset."""

from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path
import re

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter


ROOT = Path(__file__).resolve().parents[1]


def department_names() -> dict[int, str]:
    source = (ROOT / "data/03_insert_reference_dimensions.sql").read_text(
        encoding="utf-8", errors="replace"
    )
    pattern = re.compile(
        r"VALUES \('DEP(\d+)', '[^']*', (?:'[^']*'|NULL), "
        r"(?:'([^']*)'|NULL),"
    )
    return {int(number): name for number, name in pattern.findall(source) if name}


def scenario_metrics():
    annual = defaultdict(lambda: [0, 0])
    departments = defaultdict(lambda: [0, 0, 0, 0])

    for n in range(1, 50_001):
        if n <= 5_000:
            year, sequence = 2020, n - 1
        elif n <= 11_000:
            year, sequence = 2021, n - 5_001
        elif n <= 18_500:
            year, sequence = 2022, n - 11_001
        elif n <= 27_000:
            year, sequence = 2023, n - 18_501
        elif n <= 37_500:
            year, sequence = 2024, n - 27_001
        else:
            year, sequence = 2025, n - 37_501

        days = 366 if year in (2020, 2024) else 365
        visit_date = date(year, 1, 1) + timedelta(
            days=((sequence * 37) + (sequence // 7) * 11) % days
        )

        if n % 20 in (0, 1, 2):
            department = 20
        elif n % 20 in (3, 4):
            department = 1
        else:
            department = ((n * 17 + (n // 7) * 5) % 33) + 1

        diagnosis = ((n * 11 + department * 3 + (n // 17)) % 40) + 1
        treatment = (
            ((diagnosis - 1) % 30) + 1
            if n % 10 <= 6
            else ((n * 13 + department) % 30) + 1
        )
        base_wait = 50 if department == 20 else 24 if department == 1 else 12 + (department % 7) * 4
        wait = base_wait + ((n * 17) % 31) + (8 if visit_date.weekday() >= 5 else 0)
        bill = (
            2_500
            + department * 475
            + treatment * 190
            + ((n * 7_919) % 35_000)
            + (9_000 if department == 20 else 0)
        )
        satisfaction = 5 if wait <= 25 else 4 if wait <= 40 else 3 if wait <= 55 else 2 if wait <= 70 else 1

        annual[year][0] += 1
        annual[year][1] += bill
        values = departments[department]
        values[0] += 1
        values[1] += bill
        values[2] += wait
        values[3] += satisfaction

    return annual, departments


def main() -> None:
    names = department_names()
    annual, departments = scenario_metrics()

    plt.rcParams.update(
        {
            "font.family": "DejaVu Sans",
            "font.size": 10,
            "axes.titleweight": "bold",
            "axes.edgecolor": "#cbd5e1",
            "axes.labelcolor": "#334155",
            "xtick.color": "#475569",
            "ytick.color": "#475569",
        }
    )
    fig, (growth_ax, service_ax) = plt.subplots(1, 2, figsize=(14, 5.7))
    fig.patch.set_facecolor("#f8fafc")
    for axis in (growth_ax, service_ax):
        axis.set_facecolor("#ffffff")
        axis.spines[["top", "right"]].set_visible(False)
        axis.grid(axis="y", color="#e2e8f0", linewidth=0.8, zorder=0)

    years = sorted(annual)
    visits = [annual[year][0] for year in years]
    revenue = [annual[year][1] / 1_000_000 for year in years]
    bars = growth_ax.bar(years, visits, color="#2563eb", width=0.65, zorder=2)
    growth_ax.set_title("Annual demand and billed revenue", loc="left")
    growth_ax.set_ylabel("Patient visits")
    growth_ax.set_ylim(0, 14_500)
    growth_ax.yaxis.set_major_formatter(FuncFormatter(lambda value, _: f"{value / 1000:g}k"))
    growth_ax.bar_label(bars, labels=[f"{value / 1000:g}k" for value in visits], padding=4, color="#1e293b")

    revenue_ax = growth_ax.twinx()
    revenue_ax.plot(years, revenue, color="#f97316", marker="o", linewidth=2.2, zorder=3)
    revenue_ax.set_ylabel("Billed revenue (₹ millions)", color="#9a3412")
    revenue_ax.tick_params(axis="y", colors="#9a3412")
    revenue_ax.spines[["top", "left"]].set_visible(False)
    revenue_ax.spines["right"].set_color("#fed7aa")
    revenue_ax.set_ylim(0, 450)
    for year, amount in zip(years, revenue):
        revenue_ax.annotate(
            f"₹{amount:.0f}m",
            (year, amount),
            xytext=(0, 9),
            textcoords="offset points",
            ha="center",
            color="#9a3412",
            fontsize=9,
        )

    for number, values in departments.items():
        volume, _, total_wait, total_satisfaction = values
        average_wait = total_wait / volume
        average_satisfaction = total_satisfaction / volume
        if number == 20:
            color, size, alpha = "#dc2626", 150, 0.95
        elif number == 1:
            color, size, alpha = "#f59e0b", 120, 0.95
        else:
            color, size, alpha = "#64748b", 35 + volume / 55, 0.45
        service_ax.scatter(
            average_wait,
            average_satisfaction,
            s=size,
            color=color,
            alpha=alpha,
            edgecolors="white",
            linewidth=0.7,
            zorder=3,
        )

    for number, offset in ((20, (-108, -7)), (1, (8, 8))):
        volume, _, total_wait, total_satisfaction = departments[number]
        service_ax.annotate(
            f"{names[number]}\n{volume:,} visits",
            (total_wait / volume, total_satisfaction / volume),
            xytext=offset,
            textcoords="offset points",
            color="#1e293b",
            fontsize=9,
            arrowprops={"arrowstyle": "-", "color": "#94a3b8", "lw": 0.8},
        )

    service_ax.set_title("Department service-risk profile", loc="left")
    service_ax.set_xlabel("Average wait (minutes)")
    service_ax.set_ylabel("Average satisfaction (1–5)")
    service_ax.set_xlim(20, 72)
    service_ax.set_ylim(1.45, 4.65)
    service_ax.grid(axis="x", color="#e2e8f0", linewidth=0.8, zorder=0)

    fig.suptitle(
        "Hospital patient visits — executive analysis",
        x=0.06,
        y=1.02,
        ha="left",
        fontsize=18,
        fontweight="bold",
        color="#0f172a",
    )
    fig.text(
        0.06,
        0.005,
        "Deterministic synthetic scenario · 50,000 visits · 2020–2025",
        color="#64748b",
        fontsize=9,
    )
    fig.tight_layout(rect=(0.02, 0.04, 0.99, 0.95), w_pad=3.5)

    output = ROOT / "results/executive_summary.png"
    fig.savefig(output, dpi=180, bbox_inches="tight", facecolor=fig.get_facecolor())
    print(output)


if __name__ == "__main__":
    main()
