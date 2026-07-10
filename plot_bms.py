#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
plot_bms.py  —  Visualizador interativo do BMS + modelo de bateria reativo
============================================================================

O que faz
---------
1. (opcional) Compila e roda a simulacao Verilog com o Icarus Verilog
   (iverilog + vvp), gerando o arquivo de forma de onda `tb_bms_reativo.vcd`.
2. Le esse VCD (parser proprio, sem dependencias externas) e detecta
   automaticamente o `timescale` para rotular o eixo do tempo.
3. Gera um painel HTML interativo (plotly) com visual minimalista:
     - Uma FAIXA DE FASES no topo, nomeando cada caso de teste do testbench
       (I2C, T1 OV, T2 UV, T3 OT, T4 LK, T5 Balanceamento, T6 SOC, T7 Reativo),
       com bandas suaves descendo por todos os graficos.
     - Tensao das 4 celulas + limites OV/UV
     - Temperatura + limite OT
     - Corrente + limite de fuga (LK)
     - SOC (estado de carga)
     - Flags de falha (OV / UV / OT / LK / BAL)
     - Permissao do BMS (CHG_EN / DSCHG_EN) vs atividade REAL
     - Comando de balanceamento por celula (BAL_EN_1..4)
     - Estado da FSM

A faixa de fases depende do sinal `fase` que o testbench dumpa no VCD.
Se ele nao existir, o painel e gerado normalmente, so sem as bandas.

Uso
---
    python plot_bms.py                 # compila, roda e plota (padrao)
    python plot_bms.py --no-run        # so le o .vcd existente e plota
    python plot_bms.py --vcd outro.vcd # usa outro arquivo de onda
    python plot_bms.py --out saida.html
    python plot_bms.py --open          # abre o HTML no navegador ao final

Requisitos
----------
    pip install plotly
    Icarus Verilog no PATH (comandos `iverilog` e `vvp`) -- so para --run.
"""

import argparse
import os
import subprocess
import sys
import webbrowser

# ---------------------------------------------------------------------------
# Configuracao do projeto
# ---------------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))

TOP_MODULE = "tb_bms_reativo"
DEFAULT_VCD = "tb_bms_reativo.vcd"

SIM_FILES = [
    "tb_bms_reativo.v",
    "top_bms.v",
    "bms_regs_entrada.v",
    "bms_rom.v",
    "i2c_slave_controller.v",       # module bms_i2c_slave_config
    "bms_mux_A.v",
    "bms_mux_B.v",
    "bms_ula.v",
    "bms_reg_status.v",
    "bms_soc_coulomb.v",
    "bms_control_potencia.v",
    "bms_control_balanceamento.v",
    "bms_FSM.v",
    "bms_battery_model.v",
]

# Estados da FSM (bms_FSM.v) -> rotulo legivel
FSM_STATES = {
    0: "INIT", 1: "READ_SENSORS", 2: "CHECK_OV", 3: "CHECK_UV",
    4: "CHECK_OT", 5: "FAULT", 6: "CHECK_LK", 7: "CALC_BAL_SOC",
}

# Codigo de fase (reg `fase` no testbench) -> (rotulo, cor)
PHASE_STYLE = {
    0: ("init",              "#9aa5b1"),
    1: ("I2C · config",      "#64748b"),
    2: ("T1 · Sobretensão",  "#ef4444"),
    3: ("T2 · Subtensão",    "#8b5cf6"),
    4: ("T3 · Sobretemp.",   "#f97316"),
    5: ("T4 · Sobrecorr.",   "#0ea5e9"),
    6: ("T5 · Balanceam.",   "#22c55e"),
    7: ("T6 · SOC",          "#14b8a6"),
    8: ("T7 · Reativo",      "#6366f1"),
    9: ("fim",               "#9aa5b1"),
}

# Rotulo curto para faixas de fase estreitas (evita sobreposicao de texto)
PHASE_SHORT = {
    0: "init", 1: "I2C", 2: "T1", 3: "T2", 4: "T3",
    5: "T4", 6: "T5", 7: "T6", 8: "T7", 9: "fim",
}

FONT = "Inter, 'Segoe UI', system-ui, -apple-system, sans-serif"
INK = "#334155"
MUTED = "#64748b"
GRID = "#eef2f7"
CELL_COLORS = ["#2563eb", "#16a34a", "#f59e0b", "#dc2626"]
UNIT_SEC = {"s": 1.0, "ms": 1e-3, "us": 1e-6, "ns": 1e-9, "ps": 1e-12, "fs": 1e-15}


# ---------------------------------------------------------------------------
# Passo 1 -- compilar e rodar a simulacao (iverilog + vvp)
# ---------------------------------------------------------------------------
def run_simulation(project_dir):
    from shutil import which

    if not (which("iverilog") and which("vvp")):
        print("[AVISO] iverilog/vvp nao encontrados no PATH.")
        print("        Pulei a compilacao. Vou tentar ler um .vcd ja existente.")
        print("        (Instale o Icarus Verilog, ou rode com --no-run.)")
        return False

    missing = [f for f in SIM_FILES if not os.path.exists(os.path.join(project_dir, f))]
    if missing:
        print("[AVISO] Arquivos .v nao encontrados: %s" % ", ".join(missing))

    out_bin = os.path.join(project_dir, "bms_sim.out")
    files = [f for f in SIM_FILES if os.path.exists(os.path.join(project_dir, f))]

    print("[1/3] Compilando com iverilog (-g2012)...")
    cc = subprocess.run(
        ["iverilog", "-g2012", "-s", TOP_MODULE, "-o", out_bin] + files,
        cwd=project_dir, capture_output=True, text=True,
    )
    if cc.stdout.strip():
        print(cc.stdout)
    if cc.returncode != 0:
        print("[ERRO] Falha na compilacao:")
        print(cc.stderr)
        return False

    print("[2/3] Rodando a simulacao com vvp...")
    rr = subprocess.run(["vvp", out_bin], cwd=project_dir, capture_output=True, text=True)
    if rr.stdout.strip():
        print("------ log da simulacao ------")
        print(rr.stdout)
        print("------------------------------")
    if rr.returncode != 0:
        print("[ERRO] Falha ao rodar a simulacao:")
        print(rr.stderr)
        return False
    return True


# ---------------------------------------------------------------------------
# Passo 2 -- parser de VCD (Icarus)
# ---------------------------------------------------------------------------
def _bits_to_int(bits):
    clean = "".join("0" if c in "xzXZ" else c for c in bits)
    if clean == "":
        return 0
    try:
        return int(clean, 2)
    except ValueError:
        return 0


def _parse_timescale(val):
    """'1ns' -> 1e-9 segundos por tick; '10ps' -> 1e-11; '1s' -> 1.0."""
    val = val.strip().replace(" ", "")
    num, i = "", 0
    while i < len(val) and (val[i].isdigit() or val[i] == "."):
        num += val[i]
        i += 1
    unit = val[i:] or "s"
    try:
        mult = float(num) if num else 1.0
    except ValueError:
        mult = 1.0
    return mult * UNIT_SEC.get(unit, 1.0)


def parse_vcd(path):
    """
    Devolve:
      series       : { nome_de_topo   -> [(t_ticks, valor), ...] }  (inclui 'fase')
      limits       : { nome_de_limite -> [(t_ticks, valor), ...] }
      t_end        : maior timestamp (ticks)
      sec_per_tick : segundos por tick, lido do $timescale
    """
    TOP_WANT = {
        "V1_dig", "V2_dig", "V3_dig", "V4_dig",
        "I_dig", "T_dig", "I_DIR", "SOC_DATA_OUT",
        "OV_FLG", "UV_FLG", "OT_FLG", "LK_FLG", "BAL_FLG",
        "CHG_EN", "DSCHG_EN", "charging_now", "discharging_now",
        "bal_cmd_out", "Estado_atual", "fase",
    }
    LIMIT_WANT = {
        "lim_sobrecarga", "lim_sobredescarga",
        "lim_temp", "lim_corrente_fuga", "lim_corrente_max",
    }

    top_id, limit_id, id_targets = {}, {}, {}
    scope_depth = 0
    sec_per_tick = 1.0

    with open(path, "r", errors="replace") as fh:
        lines = fh.readlines()

    idx = 0
    grab_ts = False
    for idx, raw in enumerate(lines):
        line = raw.strip()
        if not line:
            continue
        if grab_ts and not line.startswith("$"):
            sec_per_tick = _parse_timescale(line)
            grab_ts = False
            continue
        if line.startswith("$timescale"):
            rest = line[len("$timescale"):].strip()
            if rest and rest != "$end":
                sec_per_tick = _parse_timescale(rest)
            else:
                grab_ts = True
        elif line.startswith("$scope"):
            scope_depth += 1
        elif line.startswith("$upscope"):
            scope_depth -= 1
        elif line.startswith("$var"):
            toks = line.split()
            vid, name = toks[3], toks[4]
            if scope_depth == 1 and name in TOP_WANT and name not in top_id:
                top_id[name] = vid
                id_targets[vid] = ("top", name)
            if name in LIMIT_WANT and name not in limit_id:
                limit_id[name] = vid
                id_targets.setdefault(vid, ("lim", name))
        elif line.startswith("$enddefinitions"):
            break

    series = {name: [] for name in top_id}
    limits = {name: [] for name in limit_id}
    t = 0
    t_end = 0

    def record(vid, val):
        tgt = id_targets.get(vid)
        if tgt is None:
            return
        (series if tgt[0] == "top" else limits)[tgt[1]].append((t, val))

    for raw in lines[idx + 1:]:
        line = raw.strip()
        if not line or line.startswith("$"):
            continue
        c0 = line[0]
        if c0 == "#":
            t = int(line[1:])
            if t > t_end:
                t_end = t
        elif c0 in "bB":
            parts = line.split()
            if len(parts) >= 2:
                record(parts[1], _bits_to_int(parts[0][1:]))
        elif c0 in "rR":
            continue
        else:
            record(line[1:], 1 if c0 == "1" else 0)

    return series, limits, t_end, sec_per_tick


# ---------------------------------------------------------------------------
# Passo 3 -- painel interativo (plotly)
# ---------------------------------------------------------------------------
def choose_xunit(t_end, sec_per_tick):
    """Escolhe a unidade do eixo do tempo. Devolve (xscale, rotulo)."""
    max_sec = t_end * sec_per_tick
    for unit, f in [("s", 1), ("ms", 1e3), ("us", 1e6), ("ns", 1e9), ("ps", 1e12)]:
        if max_sec * f >= 1 or unit == "ps":
            label = "µs" if unit == "us" else unit
            return sec_per_tick * f, "tempo (%s)" % label
    return 1.0, "tempo"


def _step_xy(pairs, t_end, xscale):
    if not pairs:
        return [], []
    xs = [p[0] * xscale for p in pairs]
    ys = [p[1] for p in pairs]
    if xs and xs[-1] < t_end * xscale:
        xs.append(t_end * xscale)
        ys.append(ys[-1])
    return xs, ys


def phase_intervals(pairs, t_end, xscale):
    """[(t_ticks,code)] -> [(t0, t1, code)] fundindo segmentos iguais."""
    if not pairs:
        return []
    segs = []
    for i, (t, code) in enumerate(pairs):
        t0 = t * xscale
        t1 = (pairs[i + 1][0] if i + 1 < len(pairs) else t_end) * xscale
        if t1 <= t0:
            continue
        if segs and segs[-1][2] == code and abs(segs[-1][1] - t0) < 1e-12:
            segs[-1] = (segs[-1][0], t1, code)
        else:
            segs.append((t0, t1, code))
    return segs


def _rgba(hexcolor, alpha):
    h = hexcolor.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return "rgba(%d,%d,%d,%.3f)" % (r, g, b, alpha)


def build_dashboard(series, limits, t_end, sec_per_tick, out_html, vcd_name):
    try:
        import plotly.graph_objects as go
        from plotly.subplots import make_subplots
    except ImportError:
        sys.exit("[ERRO] plotly nao instalado. Rode:  pip install plotly")

    xscale, xlabel = choose_xunit(t_end, sec_per_tick)

    def xy(name, src=series):
        return _step_xy(src.get(name, []), t_end, xscale)

    def has(name, src=series):
        return bool(src.get(name))

    # Linha 1 = ribbon de fases; linhas 2..9 = paineis de sinais
    titles = [
        "",
        "Tensão das células + limites OV / UV",
        "Temperatura + limite OT",
        "Corrente + limite de fuga (LK)",
        "SOC — Estado de carga",
        "Flags de falha / status",
        "Permissão do BMS   vs   atividade REAL",
        "Balanceamento por célula (bypass)",
        "Estado da FSM",
    ]
    fig = make_subplots(
        rows=9, cols=1, shared_xaxes=True, vertical_spacing=0.026,
        subplot_titles=titles,
        row_heights=[0.42, 1.45, 0.95, 0.95, 0.95, 1.3, 1.15, 1.15, 1.2],
    )

    # Restiliza os titulos dos subplots (alinha a esquerda, cor suave)
    for a in fig.layout.annotations:
        a.font = dict(size=12.5, color=MUTED, family=FONT)
        a.x = 0.0
        a.xanchor = "left"
        if a.text:
            a.text = "<b>%s</b>" % a.text

    SR = 1  # painel de sinais 'r' fica na linha r + SR (abaixo do ribbon)

    def add(name, row, **line):
        if not has(name):
            return
        x, y = xy(name)
        fig.add_trace(go.Scatter(x=x, y=y, mode="lines", name=name,
                                 line=dict(shape="hv", **line)), row=row + SR, col=1)

    # ---- Painel 1: tensoes + limites ----
    for i, nm in enumerate(["V1_dig", "V2_dig", "V3_dig", "V4_dig"]):
        add(nm, 1, color=CELL_COLORS[i], width=2.1)
    for lname, color, dash in [("lim_sobrecarga", "#dc2626", "dash"),
                               ("lim_sobredescarga", "#7c3aed", "dot")]:
        if has(lname, limits):
            x, y = xy(lname, limits)
            fig.add_trace(go.Scatter(x=x, y=y, mode="lines", name=lname, opacity=0.75,
                                     line=dict(shape="hv", color=color, width=1.3, dash=dash)),
                          row=1 + SR, col=1)

    # ---- Painel 2: temperatura ----
    add("T_dig", 2, color="#ea580c", width=2.1)
    if has("lim_temp", limits):
        x, y = xy("lim_temp", limits)
        fig.add_trace(go.Scatter(x=x, y=y, mode="lines", name="lim_temp", opacity=0.75,
                                 line=dict(shape="hv", color="#dc2626", width=1.3, dash="dash")),
                      row=2 + SR, col=1)

    # ---- Painel 3: corrente ----
    add("I_dig", 3, color="#0891b2", width=2.1)
    if has("lim_corrente_fuga", limits):
        x, y = xy("lim_corrente_fuga", limits)
        fig.add_trace(go.Scatter(x=x, y=y, mode="lines", name="lim_corrente_fuga", opacity=0.75,
                                 line=dict(shape="hv", color="#dc2626", width=1.3, dash="dash")),
                      row=3 + SR, col=1)

    # ---- Painel 4: SOC (com area) ----
    if has("SOC_DATA_OUT"):
        x, y = xy("SOC_DATA_OUT")
        fig.add_trace(go.Scatter(x=x, y=y, mode="lines", name="SOC", showlegend=False,
                                 line=dict(shape="hv", color="#0d9488", width=2.4),
                                 fill="tozeroy", fillcolor="rgba(13,148,136,0.12)"),
                      row=4 + SR, col=1)

    # ---- faixas binarias empilhadas (blocos digitais preenchidos) ----
    def stacked_binary(items, row):
        ticks, texts = [], []
        present = [it for it in items if it[2]]
        for i, (name, color, pairs, sub) in enumerate(present):
            x, y = _step_xy([(t, i + 0.78 * v) for t, v in pairs], t_end, xscale)
            base = [i] * len(x)
            fig.add_trace(go.Scatter(x=x, y=base, mode="lines", line=dict(width=0),
                                     hoverinfo="skip", showlegend=False), row=row + SR, col=1)
            fig.add_trace(go.Scatter(x=x, y=y, mode="lines", name=name, showlegend=False,
                                     line=dict(shape="hv", color=color, width=2),
                                     fill="tonexty", fillcolor=_rgba(color, 0.16)),
                          row=row + SR, col=1)
            ticks.append(i + 0.32)
            texts.append(sub)
        return ticks, texts, len(present)

    # ---- Painel 5: flags ----
    flag_src = [("OV_FLG", "#dc2626", "OV"), ("UV_FLG", "#7c3aed", "UV"),
                ("OT_FLG", "#ea580c", "OT"), ("LK_FLG", "#0891b2", "LK"),
                ("BAL_FLG", "#16a34a", "BAL")]
    f_ticks, f_text, f_n = stacked_binary(
        [(n, c, series.get(n, []), lbl) for n, c, lbl in flag_src], 5)

    # ---- Painel 6: permissao vs atividade real ----
    act_src = [("CHG_EN", "#2563eb", "CHG_EN (perm.)"),
               ("DSCHG_EN", "#f59e0b", "DSCHG_EN (perm.)"),
               ("charging_now", "#16a34a", "charging_now (real)"),
               ("discharging_now", "#dc2626", "discharging_now (real)")]
    a_ticks, a_text, a_n = stacked_binary(
        [(n, c, series.get(n, []), lbl) for n, c, lbl in act_src], 6)

    # ---- Painel 7: balanceamento por celula ----
    b_ticks, b_text, b_n = [], [], 0
    if has("bal_cmd_out"):
        b_items = [("BAL_EN_%d" % (bit + 1), CELL_COLORS[bit],
                    [(t, (v >> bit) & 1) for t, v in series["bal_cmd_out"]],
                    "cél %d" % (bit + 1)) for bit in range(4)]
        b_ticks, b_text, b_n = stacked_binary(b_items, 7)

    # ---- Painel 8: FSM ----
    if has("Estado_atual"):
        x, y = xy("Estado_atual")
        fig.add_trace(go.Scatter(x=x, y=y, mode="lines", name="FSM", showlegend=False,
                                 line=dict(shape="hv", color="#4338ca", width=2)),
                      row=8 + SR, col=1)

    # ---- FAIXA DE FASES (ribbon, linha 1) + bandas de fundo ----
    segs = phase_intervals(series.get("fase", []), t_end, xscale)
    span = (t_end * xscale) or 1.0
    for (t0, t1, code) in segs:
        full, color = PHASE_STYLE.get(code, ("?", "#94a3b8"))
        fig.add_vrect(x0=t0, x1=t1, fillcolor=color, opacity=0.06,
                      line_width=0, layer="below", row="all", col=1)
        fig.add_shape(type="rect", x0=t0, x1=t1, y0=0, y1=1,
                      xref="x", yref="y", fillcolor=color, opacity=0.9,
                      line=dict(color="white", width=1), layer="above")
        # rotulo adaptativo: nome completo em faixas largas, codigo curto nas
        # medias e nada nas muito estreitas -> nunca sobrepoe texto
        frac = (t1 - t0) / span
        text = full if frac >= 0.08 else (PHASE_SHORT.get(code, "") if frac >= 0.02 else "")
        if text:
            fig.add_annotation(x=(t0 + t1) / 2, y=0.5, xref="x", yref="y",
                               text=text, showarrow=False,
                               font=dict(color="white", size=10, family=FONT))

    # ---- eixos ----
    fig.update_yaxes(row=1, col=1, range=[0, 1], visible=False, fixedrange=True)
    fig.update_yaxes(title_text="dig", row=1 + SR, col=1)
    fig.update_yaxes(title_text="dig", row=2 + SR, col=1)
    fig.update_yaxes(title_text="dig", row=3 + SR, col=1)
    fig.update_yaxes(title_text="0–1000", row=4 + SR, col=1)
    if f_ticks:
        fig.update_yaxes(tickvals=f_ticks, ticktext=f_text, range=[-0.2, f_n], row=5 + SR, col=1)
    if a_ticks:
        fig.update_yaxes(tickvals=a_ticks, ticktext=a_text, range=[-0.2, a_n], row=6 + SR, col=1)
    if b_ticks:
        fig.update_yaxes(tickvals=b_ticks, ticktext=b_text, range=[-0.2, max(b_n, 1)], row=7 + SR, col=1)
    fig.update_yaxes(tickvals=list(FSM_STATES.keys()),
                     ticktext=["%d · %s" % (k, v) for k, v in FSM_STATES.items()],
                     range=[-0.3, 7.3], row=8 + SR, col=1)
    fig.update_xaxes(title_text=xlabel, row=9, col=1)

    fig.update_xaxes(showgrid=True, gridcolor=GRID, zeroline=False,
                     showline=False, ticks="outside", tickcolor=GRID)
    fig.update_yaxes(showgrid=True, gridcolor=GRID, zeroline=False)
    fig.update_yaxes(showgrid=False, row=1, col=1)

    fig.update_layout(
        title=dict(
            text="<b>BMS + modelo de bateria reativo</b><br>"
                 "<span style='font-size:13px;color:%s'>"
                 "malha fechada · fases dos testes destacadas · %s</span>" % (MUTED, vcd_name),
            x=0.008, xanchor="left", font=dict(size=22, family=FONT, color=INK),
        ),
        height=1820, hovermode="x unified",
        font=dict(family=FONT, size=12, color=INK),
        plot_bgcolor="white", paper_bgcolor="white",
        legend=dict(orientation="h", yanchor="top", y=-0.03, x=0.5, xanchor="center",
                    font=dict(size=11), bgcolor="rgba(255,255,255,0)"),
        margin=dict(l=120, r=28, t=104, b=96),
        hoverlabel=dict(font_size=11, font_family=FONT),
    )

    fig.write_html(out_html, include_plotlyjs="cdn",
                   config={"displaylogo": False, "scrollZoom": True})
    return segs


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Visualizador interativo do BMS reativo.")
    ap.add_argument("--vcd", default=None)
    ap.add_argument("--run", dest="run", action="store_true", default=True)
    ap.add_argument("--no-run", dest="run", action="store_false")
    ap.add_argument("--out", default=None)
    ap.add_argument("--open", action="store_true")
    ap.add_argument("--project-dir", default=HERE)
    args = ap.parse_args()

    project_dir = os.path.abspath(args.project_dir)
    vcd_path = args.vcd or os.path.join(project_dir, DEFAULT_VCD)
    out_html = args.out or os.path.join(project_dir, "bms_visualizacao.html")

    if args.run:
        run_simulation(project_dir)

    if not os.path.exists(vcd_path):
        sys.exit("[ERRO] VCD nao encontrado: %s\n"
                 "       Rode a simulacao (padrao) ou informe --vcd." % vcd_path)

    print("[3/3] Lendo %s e montando o painel..." % os.path.basename(vcd_path))
    series, limits, t_end, spt = parse_vcd(vcd_path)

    achou = [n for n, v in series.items() if v and n != "fase"]
    if not achou:
        sys.exit("[ERRO] Nenhum sinal reconhecido no VCD. Confira o testbench.")

    xscale, xlabel = choose_xunit(t_end, spt)
    print("       Sinais: %s" % ", ".join(sorted(achou)))
    print("       Duracao: %.3f %s" % (t_end * xscale, xlabel.split("(")[-1].rstrip(")")))

    segs = build_dashboard(series, limits, t_end, spt, out_html, os.path.basename(vcd_path))
    if segs:
        print("       Fases detectadas:")
        for t0, t1, code in segs:
            print("         %-16s %10.2f -> %10.2f" % (PHASE_STYLE.get(code, ("?",))[0], t0, t1))
    else:
        print("       (sinal 'fase' ausente no VCD -> painel sem bandas de fase)")

    print("\n[OK] Painel gerado: %s" % out_html)
    if args.open:
        webbrowser.open("file://" + os.path.abspath(out_html))


if __name__ == "__main__":
    main()
