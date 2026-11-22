// RTL test shim: name-based state access to the Verilated pipelined DSP core (python ctypes driven).
#include "Vc5x_core.h"
#include "Vc5x_core___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <map>
#include <vector>
#define RP(c) ((c)->d->rootp)
struct R {
    Vc5x_core *d;
    std::map<uint16_t, uint16_t> io_rd;
    std::vector<std::pair<uint16_t, uint16_t>> io_wr;
    int io_seen; uint16_t io_val; int io_delay, io_wait;
    int irq_pend; uint16_t irq_bits;
    uint64_t nretire_last; uint64_t ticks;
    uint32_t cycles0;
    std::vector<uint64_t> snoop;      /* every mem_wr_pulse seen: pmem << 32 | addr << 16 | data */
};
static void tick(R *c)
{
    Vc5x_core *d = c->d;
    d->clk = 0;
    if (c->irq_pend) d->irq_i = c->irq_bits;
    d->eval();
    if (d->io_req) {
        if (!c->io_seen) {
            c->io_seen = 1;
            if (d->io_rd) { auto it = c->io_rd.find(d->io_port); c->io_val = it == c->io_rd.end() ? 0 : it->second; }
            else c->io_wr.push_back({(uint16_t)d->io_port, (uint16_t)d->io_wdata});
        }
        if (c->io_wait < c->io_delay) { c->io_wait++; d->io_ack = 0; }      /* the host side is slow: hold the ack for io_delay clocks */
        else { d->io_ack = 1; d->io_rdata = c->io_val; }
    } else { c->io_seen = 0; c->io_wait = 0; d->io_ack = 0; }
    d->eval();
    d->clk = 1;
    d->eval();
    if (c->irq_pend) { d->irq_i = 0; c->irq_pend = 0; c->irq_bits = 0; }
    if (d->mem_wr_pulse) c->snoop.push_back(((uint64_t)(d->mem_wr_pmem ? 1 : 0) << 32) | ((uint64_t)d->mem_wr_addr << 16) | d->mem_wr_data);
    c->ticks++;
}
extern "C" {
void r_ser_tick(R *c, int rx) { c->d->ser_rx = (uint16_t)rx; c->d->ser_tick = 1; tick(c); c->d->ser_tick = 0; }       /* one serial-port tick (the AIC's frame word) */
void r_set_ivec_ind(R *c, int i, uint16_t a) { int bit = i * 16, w = bit / 32, o = bit % 32; c->d->ivec_ind_i[w] = (c->d->ivec_ind_i[w] & ~(0xFFFFu << o)) | ((uint32_t)a << o); }
uint32_t r_io_wr_count(R *c) { return (uint32_t)c->io_wr.size(); }
void r_io_wr_get(R *c, uint32_t i, uint16_t *port, uint16_t *val) { *port = c->io_wr[i].first; *val = c->io_wr[i].second; }
void r_io_delay(R *c, int n) { c->io_delay = n; }
uint32_t r_snoop_n(R *c) { return (uint32_t)c->snoop.size(); }
uint64_t r_snoop(R *c, uint32_t i) { return i < c->snoop.size() ? c->snoop[i] : 0; }
R *r_new(void)
{
    R *c = new R();
    c->d = new Vc5x_core;
    c->d->step_i = 1; c->d->xint_mode = 1; c->d->rst_n = 0; c->d->bio_i = 0; c->d->bp_en_i = 0;
    for (int i = 0; i < 9; i++) { int bit = i * 16, w = bit / 32, o = bit % 32; c->d->ivec_ind_i[w] = (c->d->ivec_ind_i[w] & ~(0xFFFFu << o)) | ((uint32_t)0 << o); }
    for (int i = 0; i < 4; i++) tick(c);
    return c;
}
void r_free(R *c) { delete c->d; delete c; }
void r_poke_pmem(R *c, uint16_t a, uint16_t v) { RP(c)->c5x_core__DOT__u_mem__DOT__pmem[a] = v; RP(c)->c5x_core__DOT__u_mem__DOT__pmem2[a] = v; }
void r_poke_dmem(R *c, uint16_t a, uint16_t v) { if (a < 0x1000) RP(c)->c5x_core__DOT__u_mem__DOT__dmem[a] = v;
    if (a >= 0x100 && a < 0x300) RP(c)->c5x_core__DOT__u_mem__DOT__shadow_b0[a - 0x100] = v;
    if (a >= 0x800 && a < 0xC00) RP(c)->c5x_core__DOT__u_mem__DOT__shadow_sa[a - 0x800] = v; }
uint16_t r_pm_rd(R *c, uint16_t a) { return RP(c)->c5x_core__DOT__u_mem__DOT__pmem[a]; }
uint16_t r_dm_rd(R *c, uint16_t a) { return a < 0x1000 ? RP(c)->c5x_core__DOT__u_mem__DOT__dmem[a] : 0; }
void r_reset(R *c, uint16_t pc)
{
    c->d->step_i = 0;
    c->d->rst_n = 0;
    for (int i = 0; i < 6; i++) tick(c);
    c->d->rst_n = 1;
    for (int i = 0; i < 6; i++) tick(c);   // let every reset stage settle with fetch held, then state is poked
    RP(c)->c5x_core__DOT__u_ctrl__DOT__fetch_pc_q = pc;
    c->io_wr.clear();
}
void r_io_set(R *c, uint16_t port, uint16_t v) { c->io_rd[port] = v; }
int r_io_wr_n(R *c) { return (int)c->io_wr.size(); }
uint32_t r_io_wr_at(R *c, int i) { return ((uint32_t)c->io_wr[i].first << 16) | c->io_wr[i].second; }
void r_bio(R *c, int v) { c->d->bio_i = v ? 1 : 0; }
void r_irq(R *c, int bit) { c->irq_bits |= (uint16_t)(1u << bit); c->irq_pend = 1; }
void r_bp(R *c, int slot, int en, uint16_t pc)
{
    uint32_t e = c->d->bp_en_i;
    if (en) e |= (1u << slot); else e &= ~(1u << slot);
    c->d->bp_en_i = e;
    if (slot == 0) c->d->bp_pc0_i = pc; else c->d->bp_pc1_i = pc;
}
// run until budget model cycles (timer ticks) elapse; return 1 if the pipeline drained (no retire for 24 clocks) with F stopped at a breakpoint
int r_run(R *c, uint32_t budget_cycles)
{
    Vc5x_core *d = c->d;
    d->step_i = 1;
    uint64_t t0 = c->ticks; uint32_t m0 = d->mtime_o;
    int quiet = 0;
    uint64_t last = d->retire_cnt_o;
    while ((uint32_t)(d->mtime_o - m0) < budget_cycles && c->ticks - t0 < 3000000) {
        tick(c);
        if (d->retire_cnt_o != last) { last = d->retire_cnt_o; quiet = 0; } else quiet++;
        if (quiet >= 24 && d->bp_en_i && !d->idle_o) {
            uint16_t f = RP(c)->c5x_core__DOT__u_ctrl__DOT__fetch_pc_q;
            if (((d->bp_en_i & 1) && f == d->bp_pc0_i) || ((d->bp_en_i & 2) && f == d->bp_pc1_i)) return 1;
        }
    }
    return 0;
}
uint32_t r_mtime(R *c) { return c->d->mtime_o; }
uint32_t r_int(R *c, int w) { auto *r = RP(c); switch (w) {
 case 0: return r->c5x_core__DOT__u_ctrl__DOT__rst_ph_q; case 1: return r->c5x_core__DOT__u_ctrl__DOT__restore_active_q;
 case 2: return r->c5x_core__DOT__u_ctrl__DOT__sh_arcr_q; case 3: return r->c5x_core__DOT__u_ctrl__DOT__sh_indx_q;
 case 4: return r->c5x_core__DOT__u_addr__DOT__arcr_q; case 5: return r->c5x_core__DOT__u_addr__DOT__indx_q;
 case 6: return r->c5x_core__DOT__u_addr__DOT__ar_q[0]; case 7: return r->c5x_core__DOT__u_addr__DOT__ar0_dirty_q;
 case 8: return r->c5x_core__DOT__u_addr__DOT__ndx_q; case 9: return r->c5x_core__DOT__u_addr__DOT__i_wr_en;
 case 10: return r->c5x_core__DOT__u_addr__DOT__i_wr_sel; case 11: return r->c5x_core__DOT__u_addr__DOT__i_wr_data;
 case 12: return r->c5x_core__DOT__u_addr__DOT__ea_ar_wr; case 13: return r->c5x_core__DOT__u_addr__DOT__desc_ar_wr_e;
 case 14: return r->c5x_core__DOT__u_ctrl__DOT__entry_pend_q; case 15: return r->c5x_core__DOT__u_ctrl__DOT__entry_pend2_q;
 case 16: return r->c5x_core__DOT__u_ctrl__DOT__rst_addr_wr_w; case 17: return r->c5x_core__DOT__u_addr__DOT__ar0_written;
 case 18: return r->c5x_core__DOT__u_ctrl__DOT__sh_arcr_q;
 case 19: return r->c5x_core__DOT__u_addr__DOT__i_desc_ar_id; case 20: return r->c5x_core__DOT__u_addr__DOT__arp_q;
 case 21: return r->c5x_core__DOT__u_addr__DOT__i_desc_mode; case 22: return r->c5x_core__DOT__u_addr__DOT__i_desc_en;
 default: return 0; } }
uint32_t r_obs(R *c, int w) { Vc5x_core *d = c->d; switch (w) { case 0: return d->instr_done; case 1: return d->pc_o; case 2: return d->op_o; case 3: return d->retire_is_intr_o; case 4: return d->arcr_o; case 5: return d->indx_o; case 6: return d->arp_o; case 7: return d->st0_o; case 8: return d->st1_o; default: return 0; } }
void r_clock(R *c, int n) { for (int i = 0; i < n; i++) tick(c); }
void r_step(R *c, int v) { c->d->step_i = v; }
uint32_t r_dbg(R *c, int w) { auto *r = RP(c); switch (w) { case 0: return r->c5x_core__DOT__u_ctrl__DOT__fetch_pc_q; case 1: return (uint32_t)c->d->retire_cnt_o; case 2: return r->c5x_core__DOT__u_ctrl__DOT__fetch_inflight_q; case 3: return c->d->step_i; case 4: return r->c5x_core__DOT__u_ctrl__DOT__halted_q; case 5: return c->d->bp_en_i; case 6: return r->c5x_core__DOT__u_ctrl__DOT__pop_en_o; case 7: return r->c5x_core__DOT__u_ctrl__DOT__slot_done_w; case 8: return r->c5x_core__DOT__u_ctrl__DOT__slot_take_w; case 9: return r->c5x_core__DOT__u_ctrl__DOT__ds_in_slot_q; case 10: return r->c5x_core__DOT__u_ctrl__DOT__e_would_retire_w; case 11: return c->d->sp_o; case 12: return r->c5x_core__DOT__u_ctrl__DOT__d_h1a_w; case 13: return r->c5x_core__DOT__u_ctrl__DOT__d_hold_w; case 14: return r->c5x_core__DOT__u_addr__DOT__bmar_q; case 21: return r->c5x_core__DOT__u_ctrl__DOT__loop_active_q; case 22: return r->c5x_core__DOT__u_ctrl__DOT__replay_active_q; case 23: return r->c5x_core__DOT__u_ctrl__DOT__e_would_retire_w; case 24: return r->c5x_core__DOT__u_ctrl__DOT__e_hold_w; default: return 0; } }
int r_idle(R *c) { return RP(c)->c5x_core__DOT__u_ctrl__DOT__idle_q; }
void r_set(R *c, const char *name, uint32_t v)
{
    auto *r = RP(c);
    std::string n(name);
    auto &al = r->c5x_core__DOT__u_alu__DOT__acc_q;
    (void)al;
    if (n == "ACC") { r->c5x_core__DOT__u_alu__DOT__acc_q = v; return; }
    if (n == "ACCB") { r->c5x_core__DOT__u_alu__DOT__accb_q = v; return; }
    if (n == "PREG") { r->c5x_core__DOT__u_alu__DOT__preg_q = v; return; }
    if (n == "TREG0") { r->c5x_core__DOT__u_alu__DOT__treg0_q = v; return; }
    if (n == "TREG1") { r->c5x_core__DOT__u_alu__DOT__treg1_q = v & 0x1F; return; }
    if (n == "TREG2") { r->c5x_core__DOT__u_alu__DOT__treg2_q = v & 0xF; return; }
    if (n.size() == 3 && n[0] == 'A' && n[1] == 'R' && n[2] >= '0' && n[2] <= '7') { r->c5x_core__DOT__u_addr__DOT__ar_q[n[2] - '0'] = v; if (n[2] == '0') r->c5x_core__DOT__u_addr__DOT__ar0_dirty_q = 1; return; }
    auto A = [&](auto &x) -> void { (void)x; };
    (void)A;
    if (n == "ARP") { r->c5x_core__DOT__u_addr__DOT__arp_q = v & 7; return; }
    if (n == "ARB") { r->c5x_core__DOT__u_addr__DOT__arb_q = v & 7; return; }
    if (n == "OV") { r->c5x_core__DOT__u_addr__DOT__ov_q = v & 1; r->c5x_core__DOT__u_alu__DOT__ov_q = v & 1; return; }
    if (n == "OVM") { r->c5x_core__DOT__u_addr__DOT__ovm_q = v & 1; return; }
    if (n == "INTM") { r->c5x_core__DOT__u_addr__DOT__intm_q = v & 1; return; }
    if (n == "DP") { r->c5x_core__DOT__u_addr__DOT__dp_q = (v & 0x1FF) << 7; return; }
    if (n == "CNF") { r->c5x_core__DOT__u_addr__DOT__cnf_q = v & 1; return; }
    if (n == "TC") { r->c5x_core__DOT__u_addr__DOT__tc_q = v & 1; return; }
    if (n == "SXM") { r->c5x_core__DOT__u_addr__DOT__sxm_q = v & 1; return; }
    if (n == "C") { r->c5x_core__DOT__u_addr__DOT__c_q = v & 1; r->c5x_core__DOT__u_alu__DOT__c_q = v & 1; return; }
    if (n == "HM") { r->c5x_core__DOT__u_addr__DOT__hm_q = v & 1; return; }
    if (n == "XF") { r->c5x_core__DOT__u_addr__DOT__xf_q = v & 1; return; }
    if (n == "PM") { r->c5x_core__DOT__u_addr__DOT__pm_q = v & 3; return; }
    if (n == "ST0") { r->c5x_core__DOT__u_addr__DOT__arp_q = (v >> 13) & 7; uint32_t ov = (v >> 12) & 1; r->c5x_core__DOT__u_addr__DOT__ov_q = ov; r->c5x_core__DOT__u_alu__DOT__ov_q = ov; r->c5x_core__DOT__u_addr__DOT__ovm_q = (v >> 11) & 1; r->c5x_core__DOT__u_addr__DOT__intm_q = (v >> 9) & 1; r->c5x_core__DOT__u_addr__DOT__dp_q = (v & 0x1FF) << 7; return; }
    if (n == "ST1") { r->c5x_core__DOT__u_addr__DOT__arb_q = (v >> 13) & 7; r->c5x_core__DOT__u_addr__DOT__cnf_q = (v >> 12) & 1; r->c5x_core__DOT__u_addr__DOT__tc_q = (v >> 11) & 1; r->c5x_core__DOT__u_addr__DOT__sxm_q = (v >> 10) & 1; uint32_t cc = (v >> 9) & 1; r->c5x_core__DOT__u_addr__DOT__c_q = cc; r->c5x_core__DOT__u_alu__DOT__c_q = cc; r->c5x_core__DOT__u_addr__DOT__hm_q = (v >> 6) & 1; r->c5x_core__DOT__u_addr__DOT__xf_q = (v >> 4) & 1; r->c5x_core__DOT__u_addr__DOT__pm_q = v & 3; return; }
    if (n == "PMST") { r->c5x_core__DOT__u_addr__DOT__iptr_q = (v >> 11) & 0x1F; r->c5x_core__DOT__u_addr__DOT__avis_q = (v >> 7) & 1; r->c5x_core__DOT__u_addr__DOT__ovly_q = (v >> 5) & 1; r->c5x_core__DOT__u_addr__DOT__ram_q = (v >> 4) & 1; r->c5x_core__DOT__u_addr__DOT__mpmc_q = (v >> 3) & 1; r->c5x_core__DOT__u_addr__DOT__ndx_q = (v >> 2) & 1; r->c5x_core__DOT__u_addr__DOT__trm_q = (v >> 1) & 1; r->c5x_core__DOT__u_addr__DOT__braf_q = v & 1; return; }
    if (n == "NDX") { r->c5x_core__DOT__u_addr__DOT__ndx_q = v & 1; return; }
    if (n == "TRM") { r->c5x_core__DOT__u_addr__DOT__trm_q = v & 1; return; }
    if (n == "BRAF") { r->c5x_core__DOT__u_addr__DOT__braf_q = v & 1; return; }
    if (n == "IFR") { r->c5x_core__DOT__u_addr__DOT__ifr_q = v; return; }
    if (n == "IMR") { r->c5x_core__DOT__u_addr__DOT__imr_q = v; return; }
    if (n == "SP") { r->c5x_core__DOT__u_addr__DOT__sp_q = v & 7; return; }
    if (n == "PUSH") { uint32_t sp = r->c5x_core__DOT__u_addr__DOT__sp_q; r->c5x_core__DOT__u_addr__DOT__sp_q = (sp + 7) & 7; r->c5x_core__DOT__u_addr__DOT__stack_q[(sp + 7) & 7] = v; return; }
    if (n == "RPTC") { r->c5x_core__DOT__u_addr__DOT__rptc_q = (int32_t)v; return; }
    if (n == "BRCR") { r->c5x_core__DOT__u_addr__DOT__brcr_q = (int32_t)v; return; }
    if (n == "BMAR") { r->c5x_core__DOT__u_addr__DOT__bmar_q = v; return; }
    if (n == "DBMR") { r->c5x_core__DOT__u_addr__DOT__dbmr_q = v; return; }
    if (n == "INDX") { r->c5x_core__DOT__u_addr__DOT__indx_q = v; return; }
    if (n == "ARCR") { r->c5x_core__DOT__u_addr__DOT__arcr_q = v; return; }
    if (n == "CBCR") { r->c5x_core__DOT__u_addr__DOT__cbcr_q = v & 0xFF; return; }
    if (n == "CBSR1") { r->c5x_core__DOT__u_addr__DOT__cbsr1_q = v; return; }
    if (n == "CBER1") { r->c5x_core__DOT__u_addr__DOT__cber1_q = v; return; }
    if (n == "CBSR2") { r->c5x_core__DOT__u_addr__DOT__cbsr2_q = v; return; }
    if (n == "CBER2") { r->c5x_core__DOT__u_addr__DOT__cber2_q = v; return; }
    if (n == "PASR") { r->c5x_core__DOT__u_addr__DOT__pasr_q = v; return; }
    if (n == "PAER") { r->c5x_core__DOT__u_addr__DOT__paer_q = v; return; }
    if (n == "PRD") { r->c5x_core__DOT__u_mem__DOT__prd_q = v; return; }
    if (n == "TIM") { r->c5x_core__DOT__u_mem__DOT__tim_q = v; return; }
    if (n == "PC") { r->c5x_core__DOT__u_ctrl__DOT__fetch_pc_q = v; return; }
    fprintf(stderr, "r_set: unknown %s\n", name);
}
uint32_t r_get(R *c, const char *name)
{
    auto *r = RP(c);
    std::string n(name);
    Vc5x_core *d = c->d;
    if (n == "ACC") return d->acc_o;
    if (n == "ACCB") return d->accb_o;
    if (n == "PREG") return d->preg_o;
    if (n == "TREG0") return d->treg0_o;
    if (n == "TREG1") return d->treg1_o;
    if (n == "TREG2") return d->treg2_o;
    if (n.size() == 3 && n[0] == 'A' && n[1] == 'R' && n[2] >= '0' && n[2] <= '7') return r->c5x_core__DOT__u_addr__DOT__ar_q[n[2] - '0'];
    if (n == "ARP") return d->arp_o;
    if (n == "ARB") return (d->st1_o >> 13) & 7;
    if (n == "OV") return (d->st0_o >> 12) & 1;
    if (n == "OVM") return (d->st0_o >> 11) & 1;
    if (n == "INTM") return (d->st0_o >> 9) & 1;
    if (n == "DP") return d->st0_o & 0x1FF;
    if (n == "CNF") return (d->st1_o >> 12) & 1;
    if (n == "TC") return (d->st1_o >> 11) & 1;
    if (n == "SXM") return (d->st1_o >> 10) & 1;
    if (n == "C") return (d->st1_o >> 9) & 1;
    if (n == "HM") return (d->st1_o >> 6) & 1;
    if (n == "XF") return (d->st1_o >> 4) & 1;
    if (n == "PM") return d->st1_o & 3;
    if (n == "ST0") return d->st0_o;
    if (n == "ST1") return d->st1_o;
    if (n == "PMST") return d->pmst_o;
    if (n == "NDX") return (d->pmst_o >> 2) & 1;
    if (n == "TRM") return (d->pmst_o >> 1) & 1;
    if (n == "BRAF") return d->pmst_o & 1;
    if (n == "IFR") return d->ifr_o;
    if (n == "IMR") return d->imr_o;
    if (n == "SP") return d->sp_o;
    if (n == "RPTC") return (uint32_t)d->rptc_o;
    if (n == "BRCR") return (uint32_t)d->brcr_o;
    if (n == "BMAR") return d->bmar_o;
    if (n == "DBMR") return d->dbmr_o;
    if (n == "INDX") return d->indx_o;
    if (n == "ARCR") return d->arcr_o;
    if (n == "CBCR") return r->c5x_core__DOT__u_addr__DOT__cbcr_q;
    if (n == "CBSR1") return r->c5x_core__DOT__u_addr__DOT__cbsr1_q;
    if (n == "CBER1") return r->c5x_core__DOT__u_addr__DOT__cber1_q;
    if (n == "CBSR2") return r->c5x_core__DOT__u_addr__DOT__cbsr2_q;
    if (n == "CBER2") return r->c5x_core__DOT__u_addr__DOT__cber2_q;
    if (n == "PRD") return d->obs_prd_o;
    if (n == "TIM") return d->obs_tim_o;
    if (n == "CWSR") return d->obs_cwsr_o;
    if (n == "PC") return d->pc_o;
    if (n == "IDLE") return r->c5x_core__DOT__u_ctrl__DOT__idle_q;
    if (n == "PASR") return d->pasr_o;
    if (n == "PAER") return d->paer_o;
    return 0xDEADDEAD;
}
}
