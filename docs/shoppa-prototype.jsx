import React, { useState, useEffect, useRef } from "react";
import {
  ShoppingCart, Home, Search, User, Plus, Check, ChevronLeft, ChevronRight,
  Users, Bell, Zap, Tag, TrendingDown, Clock, Star, Mic, X, Wifi, WifiOff,
  ScanLine, Share2, ChefHat, Package, ArrowRight, Sparkles, MapPin, Crown
} from "lucide-react";

// ─── Design tokens (from Shoppa system) ───────────────────────────
const C = {
  obsidian: "#0B0E14",
  panel: "#12161F",
  panel2: "#1A1F2B",
  line: "#252B38",
  amber: "#F5A623",
  amberBright: "#FFB627",
  gold: "#E8B339",
  green: "#3DD68C",
  rose: "#F4476B",
  blue: "#5B9BFF",
  violet: "#9B7BFF",
  ink: "#F4F1EA",
  mist: "#8A92A6",
  faint: "#5A6275",
};

const ZAR = (cents) =>
  "R" + (cents / 100).toLocaleString("en-ZA", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

// ─── Seed data ────────────────────────────────────────────────────
const STORES = [
  { id: "checkers", name: "Checkers", tag: "60/60", color: C.green },
  { id: "pnp", name: "Pick n Pay", tag: "ASAP!", color: C.rose },
  { id: "spar", name: "SPAR", tag: "2u", color: "#2FA84F" },
  { id: "woolies", name: "Woolworths", tag: "Dash", color: C.ink },
];

const PRODUCTS = {
  milk:    { name: "Full Cream Milk 2L", emoji: "🥛", prices: { checkers: 3299, pnp: 3450, spar: 3399, woolies: 3899 } },
  bread:   { name: "Brown Bread 700g", emoji: "🍞", prices: { checkers: 1799, pnp: 1699, spar: 1850, woolies: 2299 } },
  eggs:    { name: "Large Eggs ×18", emoji: "🥚", prices: { checkers: 5499, pnp: 5299, spar: 5699, woolies: 6499 } },
  chicken: { name: "Chicken Breasts 1kg", emoji: "🍗", prices: { checkers: 8999, pnp: 9499, spar: 8799, woolies: 11999 } },
  rice:    { name: "Basmati Rice 2kg", emoji: "🍚", prices: { checkers: 6499, pnp: 6299, spar: 6599, woolies: 7899 } },
  coffee:  { name: "Ground Coffee 250g", emoji: "☕", prices: { checkers: 7999, pnp: 8299, spar: 7799, woolies: 9499 } },
  bananas: { name: "Bananas 1kg", emoji: "🍌", prices: { checkers: 2499, pnp: 2399, spar: 2599, woolies: 2999 } },
  cheese:  { name: "Cheddar Cheese 800g", emoji: "🧀", prices: { checkers: 9999, pnp: 10499, spar: 9799, woolies: 12999 } },
};

const cheapest = (key) => {
  const p = PRODUCTS[key].prices;
  return Math.min(...Object.values(p));
};

const INITIAL_LISTS = [
  {
    id: "groceries", title: "Monthly Groceries", category: "Groceries", icon: "🛒",
    recurring: true, collaborators: ["TN", "ZK"], accent: C.amber,
    items: [
      { key: "milk", qty: 2, checked: false },
      { key: "bread", qty: 1, checked: false },
      { key: "eggs", qty: 1, checked: false },
      { key: "chicken", qty: 2, checked: false },
      { key: "rice", qty: 1, checked: false },
      { key: "coffee", qty: 1, checked: false },
      { key: "bananas", qty: 3, checked: false },
      { key: "cheese", qty: 1, checked: false },
    ],
  },
  {
    id: "braai", title: "Saturday Braai", category: "Event", icon: "🔥",
    recurring: false, collaborators: ["MB"], accent: C.rose,
    items: [
      { key: "chicken", qty: 4, checked: false },
      { key: "bread", qty: 2, checked: false },
      { key: "cheese", qty: 1, checked: false },
    ],
  },
  {
    id: "wishlist", title: "Birthday Wishlist", category: "Wishlist", icon: "🎁",
    recurring: false, collaborators: [], accent: C.violet,
    items: [
      { key: "coffee", qty: 1, checked: false },
    ],
  },
];

// ─── Small UI atoms ───────────────────────────────────────────────
const Avatar = ({ initials, color = C.amber, size = 26 }) => (
  <div style={{
    width: size, height: size, borderRadius: "50%", background: color + "22",
    border: `1.5px solid ${color}`, color, fontSize: size * 0.4, fontWeight: 700,
    display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0,
    fontFamily: "'DM Sans', sans-serif", letterSpacing: "0.02em",
  }}>{initials}</div>
);

const Pill = ({ children, color = C.amber, solid = false }) => (
  <span style={{
    fontSize: 10.5, fontWeight: 700, letterSpacing: "0.06em", textTransform: "uppercase",
    padding: "3px 8px", borderRadius: 6, lineHeight: 1,
    background: solid ? color : color + "1E", color: solid ? C.obsidian : color,
    border: solid ? "none" : `1px solid ${color}33`,
  }}>{children}</span>
);

const StoreBadge = ({ store, size = 13 }) => (
  <span style={{ display: "inline-flex", alignItems: "baseline", gap: 4, fontSize: size, fontWeight: 600, color: C.ink }}>
    {store.name}
    <span style={{ fontSize: size * 0.72, fontWeight: 800, color: store.color }}>{store.tag}</span>
  </span>
);

// ─── Screens ──────────────────────────────────────────────────────

function HomeScreen({ lists, go, savings }) {
  const totalItems = lists.reduce((a, l) => a + l.items.length, 0);
  return (
    <div style={{ paddingBottom: 24 }}>
      <div style={{ padding: "8px 20px 4px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div>
            <div style={{ fontSize: 12, color: C.mist, fontWeight: 600, letterSpacing: "0.04em" }}>Sawubona, Ndabe 👋</div>
            <div style={{ fontFamily: "'Syne', sans-serif", fontSize: 26, fontWeight: 800, color: C.ink, marginTop: 2 }}>
              Your Mall
            </div>
          </div>
          <div style={{ position: "relative" }}>
            <Bell size={22} color={C.mist} />
            <div style={{ position: "absolute", top: -2, right: -2, width: 8, height: 8, borderRadius: "50%", background: C.amber, border: `2px solid ${C.obsidian}` }} />
          </div>
        </div>
      </div>

      {/* Hero savings card */}
      <div style={{ margin: "16px 20px 0", borderRadius: 20, padding: 20, position: "relative", overflow: "hidden",
        background: `linear-gradient(135deg, ${C.panel2} 0%, ${C.panel} 100%)`, border: `1px solid ${C.line}` }}>
        <div style={{ position: "absolute", top: -40, right: -30, width: 160, height: 160, borderRadius: "50%",
          background: `radial-gradient(circle, ${C.amber}22 0%, transparent 70%)` }} />
        <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
          <TrendingDown size={15} color={C.green} />
          <span style={{ fontSize: 11.5, color: C.mist, fontWeight: 600, letterSpacing: "0.05em", textTransform: "uppercase" }}>
            Potential savings this week
          </span>
        </div>
        <div style={{ fontFamily: "'Syne', sans-serif", fontSize: 40, fontWeight: 800, color: C.ink, marginTop: 8, lineHeight: 1 }}>
          {ZAR(savings)}
        </div>
        <div style={{ fontSize: 12.5, color: C.mist, marginTop: 8 }}>
          By shopping smart across {STORES.length} stores near you
        </div>
        <button onClick={() => go("compare")} style={btnPrimary}>
          See the breakdown <ArrowRight size={15} />
        </button>
      </div>

      {/* Quick stats */}
      <div style={{ display: "flex", gap: 10, padding: "16px 20px 4px" }}>
        {[
          { label: "Active lists", value: lists.length, icon: <Package size={15} color={C.amber} /> },
          { label: "Items", value: totalItems, icon: <ShoppingCart size={15} color={C.blue} /> },
          { label: "Trust score", value: "A+", icon: <Star size={15} color={C.gold} /> },
        ].map((s, i) => (
          <div key={i} style={{ flex: 1, background: C.panel, border: `1px solid ${C.line}`, borderRadius: 14, padding: "12px 10px" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>{s.icon}
              <span style={{ fontFamily: "'Syne', sans-serif", fontSize: 19, fontWeight: 800, color: C.ink }}>{s.value}</span>
            </div>
            <div style={{ fontSize: 10.5, color: C.faint, marginTop: 3, fontWeight: 600 }}>{s.label}</div>
          </div>
        ))}
      </div>

      {/* Lists */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "18px 20px 10px" }}>
        <span style={{ fontFamily: "'Syne', sans-serif", fontSize: 17, fontWeight: 700, color: C.ink }}>My Lists</span>
        <span style={{ fontSize: 12.5, color: C.amber, fontWeight: 600 }}>See all</span>
      </div>
      <div style={{ padding: "0 20px", display: "flex", flexDirection: "column", gap: 11 }}>
        {lists.map((l) => {
          const done = l.items.filter((i) => i.checked).length;
          const pct = Math.round((done / l.items.length) * 100) || 0;
          return (
            <button key={l.id} onClick={() => go("list", l.id)} style={{
              textAlign: "left", background: C.panel, border: `1px solid ${C.line}`, borderRadius: 16,
              padding: 15, display: "flex", gap: 13, alignItems: "center", cursor: "pointer", width: "100%",
            }}>
              <div style={{ width: 46, height: 46, borderRadius: 13, background: l.accent + "18",
                border: `1px solid ${l.accent}33`, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 22, flexShrink: 0 }}>
                {l.icon}
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  <span style={{ fontSize: 15, fontWeight: 700, color: C.ink }}>{l.title}</span>
                  {l.recurring && <Pill color={C.green}>Monthly</Pill>}
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 7 }}>
                  <div style={{ flex: 1, height: 5, background: C.panel2, borderRadius: 3, overflow: "hidden" }}>
                    <div style={{ width: pct + "%", height: "100%", background: l.accent, borderRadius: 3, transition: "width .4s" }} />
                  </div>
                  <span style={{ fontSize: 11, color: C.mist, fontWeight: 600, whiteSpace: "nowrap" }}>{done}/{l.items.length}</span>
                </div>
              </div>
              <div style={{ display: "flex", marginLeft: 2 }}>
                {l.collaborators.map((c, i) => (
                  <div key={i} style={{ marginLeft: i ? -8 : 0 }}><Avatar initials={c} size={24} color={[C.blue, C.violet, C.green][i % 3]} /></div>
                ))}
              </div>
            </button>
          );
        })}
      </div>

      {/* Pro upsell */}
      <div style={{ margin: "20px 20px 0", borderRadius: 16, padding: 16, display: "flex", gap: 13, alignItems: "center",
        background: `linear-gradient(120deg, ${C.amber}14, ${C.gold}08)`, border: `1px solid ${C.amber}33` }}>
        <ChefHat size={26} color={C.amber} />
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 13.5, fontWeight: 700, color: C.ink }}>Cooking for a crowd?</div>
          <div style={{ fontSize: 11.5, color: C.mist, marginTop: 2 }}>Scale any list by guests with Shoppa Pro</div>
        </div>
        <Crown size={18} color={C.gold} />
      </div>
    </div>
  );
}

function ListScreen({ list, go, toggleItem, openShop }) {
  if (!list) return null;
  const subtotal = list.items.reduce((a, i) => a + cheapest(i.key) * i.qty, 0);
  const done = list.items.filter((i) => i.checked).length;
  return (
    <div style={{ paddingBottom: 20 }}>
      <div style={{ padding: "4px 20px 0" }}>
        <button onClick={() => go("home")} style={backBtn}><ChevronLeft size={18} /> Mall</button>
        <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", marginTop: 10 }}>
          <div>
            <div style={{ fontFamily: "'Syne', sans-serif", fontSize: 24, fontWeight: 800, color: C.ink, display: "flex", alignItems: "center", gap: 9 }}>
              <span>{list.icon}</span>{list.title}
            </div>
            <div style={{ display: "flex", gap: 8, marginTop: 8, alignItems: "center" }}>
              <Pill color={list.accent}>{list.category}</Pill>
              {list.recurring && <Pill color={C.green}>Monthly</Pill>}
              <span style={{ display: "flex", alignItems: "center", gap: 4, fontSize: 11.5, color: C.mist }}>
                <Users size={12} /> {list.collaborators.length || "Just you"}
              </span>
            </div>
          </div>
          <button style={iconBtn}><Share2 size={16} color={C.mist} /></button>
        </div>
      </div>

      {/* live collab banner */}
      {list.collaborators.length > 0 && (
        <div style={{ margin: "14px 20px 0", padding: "9px 13px", borderRadius: 11, background: C.panel,
          border: `1px solid ${C.line}`, display: "flex", alignItems: "center", gap: 9 }}>
          <span style={{ width: 7, height: 7, borderRadius: "50%", background: C.green, boxShadow: `0 0 8px ${C.green}` }} />
          <span style={{ fontSize: 12, color: C.mist }}>
            <b style={{ color: C.ink }}>{list.collaborators[0]}</b> is editing this list now
          </span>
        </div>
      )}

      {/* items */}
      <div style={{ padding: "16px 20px 0", display: "flex", flexDirection: "column", gap: 9 }}>
        {list.items.map((it, idx) => {
          const p = PRODUCTS[it.key];
          const best = cheapest(it.key);
          const bestStore = STORES.find((s) => p.prices[s.id] === best);
          return (
            <div key={idx} onClick={() => toggleItem(list.id, idx)} style={{
              display: "flex", alignItems: "center", gap: 12, padding: 13, borderRadius: 14, cursor: "pointer",
              background: it.checked ? C.panel2 + "88" : C.panel, border: `1px solid ${it.checked ? C.line : C.line}`,
              opacity: it.checked ? 0.55 : 1, transition: "all .25s",
            }}>
              <div style={{ width: 24, height: 24, borderRadius: 8, flexShrink: 0,
                border: `2px solid ${it.checked ? C.green : C.faint}`, background: it.checked ? C.green : "transparent",
                display: "flex", alignItems: "center", justifyContent: "center", transition: "all .2s" }}>
                {it.checked && <Check size={14} color={C.obsidian} strokeWidth={3.5} />}
              </div>
              <span style={{ fontSize: 22 }}>{p.emoji}</span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 600, color: C.ink, textDecoration: it.checked ? "line-through" : "none" }}>
                  {p.name}
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 3 }}>
                  <span style={{ fontSize: 11.5, color: C.mist }}>Qty {it.qty}</span>
                  <span style={{ color: C.faint }}>·</span>
                  <span style={{ fontSize: 11.5, color: C.green, fontWeight: 600 }}>{ZAR(best)}</span>
                  <span style={{ fontSize: 10.5, color: C.faint }}>at {bestStore.name}</span>
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* footer actions */}
      <div style={{ margin: "20px 20px 0", padding: 16, borderRadius: 16, background: C.panel, border: `1px solid ${C.line}` }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span style={{ fontSize: 12.5, color: C.mist }}>Cheapest basket total</span>
          <span style={{ fontFamily: "'Syne', sans-serif", fontSize: 22, fontWeight: 800, color: C.ink }}>{ZAR(subtotal)}</span>
        </div>
        <div style={{ display: "flex", gap: 10, marginTop: 14 }}>
          <button onClick={() => go("compare")} style={{ ...btnGhost, flex: 1 }}>
            <TrendingDown size={15} /> Compare
          </button>
          <button onClick={openShop} style={{ ...btnPrimary, flex: 1, marginTop: 0 }}>
            <ShoppingCart size={15} /> Shop now
          </button>
        </div>
      </div>
    </div>
  );
}

function CompareScreen({ list, go, savings }) {
  const items = list ? list.items : INITIAL_LISTS[0].items;
  const totals = STORES.map((s) => ({
    store: s,
    total: items.reduce((a, i) => a + PRODUCTS[i.key].prices[s.id] * i.qty, 0),
  })).sort((a, b) => a.total - b.total);
  const best = totals[0].total;
  const worst = totals[totals.length - 1].total;

  return (
    <div style={{ paddingBottom: 20 }}>
      <div style={{ padding: "4px 20px 0" }}>
        <button onClick={() => go("home")} style={backBtn}><ChevronLeft size={18} /> Back</button>
        <div style={{ fontFamily: "'Syne', sans-serif", fontSize: 24, fontWeight: 800, color: C.ink, marginTop: 10 }}>
          Price Comparison
        </div>
        <div style={{ fontSize: 12.5, color: C.mist, marginTop: 4 }}>
          {list ? list.title : "Monthly Groceries"} · live from crowd-sourced prices
        </div>
      </div>

      {/* winner banner */}
      <div style={{ margin: "16px 20px 0", padding: 16, borderRadius: 16, position: "relative", overflow: "hidden",
        background: `linear-gradient(135deg, ${C.green}1A, ${C.green}08)`, border: `1px solid ${C.green}44` }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <Sparkles size={16} color={C.green} />
          <span style={{ fontSize: 11.5, color: C.green, fontWeight: 700, letterSpacing: "0.05em", textTransform: "uppercase" }}>
            Best value
          </span>
        </div>
        <div style={{ display: "flex", alignItems: "baseline", gap: 10, marginTop: 8 }}>
          <StoreBadge store={totals[0].store} size={18} />
        </div>
        <div style={{ fontSize: 12.5, color: C.mist, marginTop: 6 }}>
          Save <b style={{ color: C.green }}>{ZAR(worst - best)}</b> vs the most expensive store
        </div>
      </div>

      {/* store rows */}
      <div style={{ padding: "16px 20px 0", display: "flex", flexDirection: "column", gap: 10 }}>
        {totals.map((t, i) => {
          const ratio = (t.total - best) / (worst - best || 1);
          return (
            <div key={t.store.id} style={{ background: C.panel, border: `1px solid ${i === 0 ? C.green + "55" : C.line}`,
              borderRadius: 14, padding: 14 }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                  {i === 0
                    ? <div style={{ width: 22, height: 22, borderRadius: "50%", background: C.green, display: "flex", alignItems: "center", justifyContent: "center" }}>
                        <Check size={13} color={C.obsidian} strokeWidth={3} /></div>
                    : <span style={{ width: 22, textAlign: "center", fontSize: 13, fontWeight: 700, color: C.faint }}>{i + 1}</span>}
                  <StoreBadge store={t.store} />
                </div>
                <span style={{ fontFamily: "'Syne', sans-serif", fontSize: 17, fontWeight: 800, color: i === 0 ? C.green : C.ink }}>
                  {ZAR(t.total)}
                </span>
              </div>
              <div style={{ height: 5, background: C.panel2, borderRadius: 3, marginTop: 11, overflow: "hidden" }}>
                <div style={{ width: (100 - ratio * 55) + "%", height: "100%", borderRadius: 3,
                  background: i === 0 ? C.green : C.faint, transition: "width .5s" }} />
              </div>
              {i > 0 && <div style={{ fontSize: 11, color: C.faint, marginTop: 7 }}>+{ZAR(t.total - best)} more</div>}
            </div>
          );
        })}
      </div>

      <button onClick={() => go("delivery")} style={{ ...btnPrimary, margin: "20px 20px 0", width: "calc(100% - 40px)" }}>
        <Zap size={15} /> Compare delivery options
      </button>
    </div>
  );
}

function DeliveryScreen({ list, go }) {
  const items = list ? list.items : INITIAL_LISTS[0].items;
  const quotes = STORES.map((s, i) => {
    const sub = items.reduce((a, it) => a + PRODUCTS[it.key].prices[s.id] * it.qty, 0);
    const fee = [2500, 3500, 2900, 0][i];
    const eta = [60, 75, 90, 120][i];
    const avail = [items.length, items.length, items.length - 1, items.length][i];
    return { store: s, sub, fee, eta, avail, total: sub + fee };
  }).sort((a, b) => a.total - b.total);

  return (
    <div style={{ paddingBottom: 20 }}>
      <div style={{ padding: "4px 20px 0" }}>
        <button onClick={() => go("compare")} style={backBtn}><ChevronLeft size={18} /> Prices</button>
        <div style={{ fontFamily: "'Syne', sans-serif", fontSize: 24, fontWeight: 800, color: C.ink, marginTop: 10 }}>
          Same-Day Delivery
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 5, fontSize: 12.5, color: C.mist, marginTop: 4 }}>
          <MapPin size={12} /> Johannesburg · 4 platforms available
        </div>
      </div>

      <div style={{ padding: "16px 20px 0", display: "flex", flexDirection: "column", gap: 11 }}>
        {quotes.map((q, i) => (
          <div key={q.store.id} style={{ background: C.panel, border: `1px solid ${i === 0 ? C.amber + "55" : C.line}`,
            borderRadius: 16, padding: 15 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <StoreBadge store={q.store} size={15} />
              {i === 0 && <Pill color={C.amber} solid>Cheapest</Pill>}
            </div>
            <div style={{ display: "flex", gap: 16, marginTop: 12 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
                <Clock size={13} color={C.mist} />
                <span style={{ fontSize: 12.5, color: C.ink, fontWeight: 600 }}>{q.eta} min</span>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
                <Package size={13} color={C.mist} />
                <span style={{ fontSize: 12.5, color: q.avail < items.length ? C.rose : C.ink, fontWeight: 600 }}>
                  {q.avail}/{items.length} in stock
                </span>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
                <Zap size={13} color={C.mist} />
                <span style={{ fontSize: 12.5, color: C.ink, fontWeight: 600 }}>{q.fee === 0 ? "Free" : ZAR(q.fee)} fee</span>
              </div>
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 14,
              paddingTop: 13, borderTop: `1px solid ${C.line}` }}>
              <span style={{ fontFamily: "'Syne', sans-serif", fontSize: 19, fontWeight: 800, color: i === 0 ? C.amber : C.ink }}>
                {ZAR(q.total)}
              </span>
              <button style={{ ...btnPrimary, marginTop: 0, padding: "9px 16px", fontSize: 13 }}>
                Order <ArrowRight size={14} />
              </button>
            </div>
          </div>
        ))}
      </div>
      <div style={{ textAlign: "center", fontSize: 11, color: C.faint, marginTop: 16, padding: "0 30px" }}>
        Prices include affiliate links · Shoppa earns a small commission at no cost to you
      </div>
    </div>
  );
}

// In-store shopping mode (modal overlay)
function ShopMode({ list, close, toggleItem, online, setOnline }) {
  const [priceItem, setPriceItem] = useState(null);
  const [enteredPrice, setEnteredPrice] = useState("");
  const done = list.items.filter((i) => i.checked).length;
  const spent = list.items.filter((i) => i.checked).reduce((a, i) => a + (i.paid || cheapest(i.key)) * i.qty, 0);

  const handleCheck = (idx) => {
    if (!list.items[idx].checked) {
      setPriceItem(idx);
      setEnteredPrice((cheapest(list.items[idx].key) / 100).toFixed(2));
    } else {
      toggleItem(list.id, idx);
    }
  };
  const confirmPrice = () => {
    toggleItem(list.id, priceItem, Math.round(parseFloat(enteredPrice || 0) * 100));
    setPriceItem(null);
  };

  return (
    <div style={{ position: "absolute", inset: 0, background: C.obsidian, zIndex: 20, display: "flex", flexDirection: "column" }}>
      {/* header */}
      <div style={{ padding: "16px 20px 14px", borderBottom: `1px solid ${C.line}`,
        background: `linear-gradient(180deg, ${C.panel}, ${C.obsidian})` }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
            <ShoppingCart size={18} color={C.amber} />
            <span style={{ fontFamily: "'Syne', sans-serif", fontSize: 17, fontWeight: 800, color: C.ink }}>Shopping Mode</span>
          </div>
          <button onClick={close} style={iconBtn}><X size={17} color={C.mist} /></button>
        </div>
        {/* offline toggle */}
        <button onClick={() => setOnline(!online)} style={{
          marginTop: 12, display: "flex", alignItems: "center", gap: 8, padding: "8px 12px", width: "100%",
          borderRadius: 10, cursor: "pointer", border: `1px solid ${online ? C.line : C.amber + "55"}`,
          background: online ? C.panel : C.amber + "14" }}>
          {online ? <Wifi size={14} color={C.green} /> : <WifiOff size={14} color={C.amber} />}
          <span style={{ fontSize: 12, color: online ? C.mist : C.amber, fontWeight: 600 }}>
            {online ? "Online · synced" : "Offline mode · changes saved locally, will sync later"}
          </span>
        </button>
        <div style={{ display: "flex", justifyContent: "space-between", marginTop: 13 }}>
          <div>
            <div style={{ fontSize: 10.5, color: C.faint, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.05em" }}>Progress</div>
            <div style={{ fontFamily: "'Syne', sans-serif", fontSize: 18, fontWeight: 800, color: C.ink }}>{done}/{list.items.length}</div>
          </div>
          <div style={{ textAlign: "right" }}>
            <div style={{ fontSize: 10.5, color: C.faint, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.05em" }}>Spent so far</div>
            <div style={{ fontFamily: "'Syne', sans-serif", fontSize: 18, fontWeight: 800, color: C.amber }}>{ZAR(spent)}</div>
          </div>
        </div>
      </div>

      {/* items - big touch targets */}
      <div style={{ flex: 1, overflowY: "auto", padding: "14px 16px", display: "flex", flexDirection: "column", gap: 10 }}>
        {list.items.map((it, idx) => {
          const p = PRODUCTS[it.key];
          return (
            <button key={idx} onClick={() => handleCheck(idx)} style={{
              display: "flex", alignItems: "center", gap: 14, padding: 16, borderRadius: 16, cursor: "pointer", width: "100%", textAlign: "left",
              background: it.checked ? C.green + "12" : C.panel, border: `1.5px solid ${it.checked ? C.green + "55" : C.line}`,
              transition: "all .2s" }}>
              <div style={{ width: 30, height: 30, borderRadius: 9, flexShrink: 0,
                border: `2.5px solid ${it.checked ? C.green : C.faint}`, background: it.checked ? C.green : "transparent",
                display: "flex", alignItems: "center", justifyContent: "center" }}>
                {it.checked && <Check size={17} color={C.obsidian} strokeWidth={3.5} />}
              </div>
              <span style={{ fontSize: 27 }}>{p.emoji}</span>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 15, fontWeight: 600, color: C.ink, textDecoration: it.checked ? "line-through" : "none" }}>{p.name}</div>
                <div style={{ fontSize: 12, color: C.mist, marginTop: 3 }}>
                  Qty {it.qty}{it.checked && it.paid != null && <span style={{ color: C.green }}> · paid {ZAR(it.paid)}</span>}
                </div>
              </div>
            </button>
          );
        })}
        {done === list.items.length && (
          <div style={{ textAlign: "center", padding: 24, borderRadius: 16, background: C.green + "12", border: `1px solid ${C.green}44`, marginTop: 4 }}>
            <div style={{ fontSize: 30 }}>🎉</div>
            <div style={{ fontFamily: "'Syne', sans-serif", fontSize: 17, fontWeight: 800, color: C.ink, marginTop: 6 }}>List complete!</div>
            <div style={{ fontSize: 12.5, color: C.mist, marginTop: 4 }}>Total spent {ZAR(spent)} · +12 contribution points earned</div>
          </div>
        )}
      </div>

      {/* mic bar */}
      <div style={{ padding: "12px 16px", borderTop: `1px solid ${C.line}`, display: "flex", gap: 10, alignItems: "center", background: C.panel }}>
        <div style={{ flex: 1, fontSize: 12.5, color: C.faint }}>Tap an item to check off &amp; log its price</div>
        <button style={{ width: 44, height: 44, borderRadius: "50%", background: C.amber, border: "none", cursor: "pointer",
          display: "flex", alignItems: "center", justifyContent: "center", boxShadow: `0 4px 16px ${C.amber}44` }}>
          <Mic size={19} color={C.obsidian} />
        </button>
      </div>

      {/* price entry sheet */}
      {priceItem !== null && (
        <div style={{ position: "absolute", inset: 0, background: "rgba(0,0,0,.6)", zIndex: 30, display: "flex", alignItems: "flex-end" }}
          onClick={() => setPriceItem(null)}>
          <div onClick={(e) => e.stopPropagation()} style={{ width: "100%", background: C.panel2, borderRadius: "24px 24px 0 0",
            padding: 24, borderTop: `1px solid ${C.line}` }}>
            <div style={{ width: 40, height: 4, borderRadius: 2, background: C.faint, margin: "0 auto 18px" }} />
            <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 18 }}>
              <span style={{ fontSize: 30 }}>{PRODUCTS[list.items[priceItem].key].emoji}</span>
              <div>
                <div style={{ fontSize: 15, fontWeight: 700, color: C.ink }}>{PRODUCTS[list.items[priceItem].key].name}</div>
                <div style={{ fontSize: 12, color: C.mist, marginTop: 2 }}>Confirm the price you paid</div>
              </div>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 10, background: C.obsidian, border: `1px solid ${C.line}`,
              borderRadius: 14, padding: "14px 16px" }}>
              <span style={{ fontSize: 22, fontWeight: 800, color: C.amber, fontFamily: "'Syne', sans-serif" }}>R</span>
              <input value={enteredPrice} onChange={(e) => setEnteredPrice(e.target.value)} autoFocus inputMode="decimal" style={{
                flex: 1, background: "transparent", border: "none", outline: "none", color: C.ink,
                fontSize: 22, fontWeight: 700, fontFamily: "'Syne', sans-serif" }} />
              <ScanLine size={20} color={C.mist} />
            </div>
            <div style={{ fontSize: 11.5, color: C.faint, marginTop: 10, display: "flex", alignItems: "center", gap: 6 }}>
              <Sparkles size={12} color={C.green} /> Your price helps {STORES.length}k+ shoppers nearby
            </div>
            <button onClick={confirmPrice} style={{ ...btnPrimary, width: "100%", marginTop: 18, justifyContent: "center", padding: 15 }}>
              <Check size={16} /> Confirm &amp; check off
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Shell ────────────────────────────────────────────────────────
export default function ShoppaPrototype() {
  const [screen, setScreen] = useState("home");
  const [activeListId, setActiveListId] = useState(null);
  const [lists, setLists] = useState(INITIAL_LISTS);
  const [shopOpen, setShopOpen] = useState(false);
  const [online, setOnline] = useState(true);
  const [tab, setTab] = useState("home");

  useEffect(() => {
    const id = "shoppa-fonts";
    if (!document.getElementById(id)) {
      const l = document.createElement("link");
      l.id = id; l.rel = "stylesheet";
      l.href = "https://fonts.googleapis.com/css2?family=Syne:wght@700;800&family=DM+Sans:wght@400;500;600;700&display=swap";
      document.head.appendChild(l);
    }
  }, []);

  const go = (s, listId) => {
    if (listId !== undefined) setActiveListId(listId);
    setScreen(s);
    if (["home", "compare"].includes(s)) setTab(s === "home" ? "home" : "search");
  };

  const toggleItem = (listId, idx, paid) => {
    setLists((prev) => prev.map((l) => l.id !== listId ? l : {
      ...l, items: l.items.map((it, i) => i !== idx ? it : { ...it, checked: !it.checked, paid: !it.checked ? paid : null }),
    }));
  };

  const activeList = lists.find((l) => l.id === activeListId);
  const compareSavings = (() => {
    const items = INITIAL_LISTS[0].items;
    const t = STORES.map((s) => items.reduce((a, i) => a + PRODUCTS[i.key].prices[s.id] * i.qty, 0));
    return Math.max(...t) - Math.min(...t);
  })();

  return (
    <div style={{ minHeight: "100vh", background: "#06080C", display: "flex", alignItems: "center",
      justifyContent: "center", padding: 20, fontFamily: "'DM Sans', sans-serif" }}>
      <div style={{ width: 390, maxWidth: "100%" }}>
        {/* phone frame */}
        <div style={{ position: "relative", background: C.obsidian, borderRadius: 40, overflow: "hidden",
          border: `1px solid ${C.line}`, boxShadow: "0 40px 120px rgba(0,0,0,.6), 0 0 0 10px #0d1017",
          height: 800, display: "flex", flexDirection: "column" }}>
          {/* status bar */}
          <div style={{ padding: "12px 24px 6px", display: "flex", justifyContent: "space-between", alignItems: "center", flexShrink: 0 }}>
            <span style={{ fontSize: 13, fontWeight: 700, color: C.ink }}>9:41</span>
            <div style={{ display: "flex", alignItems: "center", gap: 6, color: C.ink }}>
              {!online && <WifiOff size={13} color={C.amber} />}
              <div style={{ display: "flex", gap: 2, alignItems: "flex-end" }}>
                {[5, 8, 11, 14].map((h, i) => <div key={i} style={{ width: 3, height: h, borderRadius: 1, background: C.ink, opacity: i === 3 ? 0.4 : 1 }} />)}
              </div>
              <div style={{ width: 22, height: 11, borderRadius: 3, border: `1.2px solid ${C.ink}`, padding: 1.5, display: "flex" }}>
                <div style={{ flex: 1, background: C.green, borderRadius: 1 }} />
              </div>
            </div>
          </div>

          {/* scroll area */}
          <div style={{ flex: 1, overflowY: "auto", overflowX: "hidden" }} className="shoppa-scroll">
            {screen === "home" && <HomeScreen lists={lists} go={go} savings={compareSavings} />}
            {screen === "list" && <ListScreen list={activeList} go={go} toggleItem={toggleItem} openShop={() => setShopOpen(true)} />}
            {screen === "compare" && <CompareScreen list={activeList} go={go} savings={compareSavings} />}
            {screen === "delivery" && <DeliveryScreen list={activeList} go={go} />}
          </div>

          {/* tab bar */}
          <div style={{ flexShrink: 0, display: "flex", padding: "10px 8px 14px", borderTop: `1px solid ${C.line}`,
            background: `linear-gradient(0deg, ${C.panel}, ${C.obsidian})` }}>
            {[
              { id: "home", icon: Home, label: "Mall", action: () => go("home") },
              { id: "search", icon: Search, label: "Compare", action: () => go("compare") },
              { id: "add", icon: Plus, label: "", action: () => go("home"), fab: true },
              { id: "lists", icon: ShoppingCart, label: "Lists", action: () => go("home") },
              { id: "profile", icon: User, label: "Profile", action: () => {} },
            ].map((t) => {
              if (t.fab) return (
                <div key={t.id} style={{ flex: 1, display: "flex", justifyContent: "center" }}>
                  <button onClick={t.action} style={{ width: 50, height: 50, borderRadius: 16, marginTop: -22, cursor: "pointer",
                    background: `linear-gradient(135deg, ${C.amberBright}, ${C.amber})`, border: `3px solid ${C.obsidian}`,
                    display: "flex", alignItems: "center", justifyContent: "center", boxShadow: `0 8px 24px ${C.amber}55` }}>
                    <Plus size={24} color={C.obsidian} strokeWidth={2.5} />
                  </button>
                </div>
              );
              const Icon = t.icon;
              const active = (screen === "home" && t.id === "home") || ((screen === "compare" || screen === "delivery") && t.id === "search");
              return (
                <button key={t.id} onClick={t.action} style={{ flex: 1, background: "none", border: "none", cursor: "pointer",
                  display: "flex", flexDirection: "column", alignItems: "center", gap: 4, padding: "4px 0" }}>
                  <Icon size={21} color={active ? C.amber : C.faint} strokeWidth={active ? 2.4 : 2} />
                  <span style={{ fontSize: 10, fontWeight: 600, color: active ? C.amber : C.faint }}>{t.label}</span>
                </button>
              );
            })}
          </div>

          {/* shop mode overlay */}
          {shopOpen && activeList && (
            <ShopMode list={activeList} close={() => setShopOpen(false)} toggleItem={toggleItem} online={online} setOnline={setOnline} />
          )}
        </div>

        {/* caption */}
        <div style={{ textAlign: "center", marginTop: 18, color: C.faint, fontSize: 12 }}>
          <span style={{ fontFamily: "'Syne', sans-serif", fontWeight: 800, color: C.amber, letterSpacing: "0.04em" }}>SHOPPA</span>
          {"  ·  "}interactive prototype · tap lists, check off items, compare prices &amp; delivery
        </div>
      </div>

      <style>{`
        .shoppa-scroll::-webkit-scrollbar { width: 0; }
        button { font-family: 'DM Sans', sans-serif; }
        * { -webkit-tap-highlight-color: transparent; }
      `}</style>
    </div>
  );
}

// ─── shared button styles ─────────────────────────────────────────
const btnPrimary = {
  marginTop: 16, display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 7,
  background: `linear-gradient(135deg, ${C.amberBright}, ${C.amber})`, color: C.obsidian,
  border: "none", borderRadius: 12, padding: "12px 18px", fontSize: 14, fontWeight: 700, cursor: "pointer",
};
const btnGhost = {
  display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 7,
  background: C.panel2, color: C.ink, border: `1px solid ${C.line}`, borderRadius: 12,
  padding: "12px 18px", fontSize: 14, fontWeight: 600, cursor: "pointer",
};
const backBtn = {
  display: "inline-flex", alignItems: "center", gap: 2, background: "none", border: "none",
  color: C.mist, fontSize: 13.5, fontWeight: 600, cursor: "pointer", padding: 0, marginLeft: -4,
};
const iconBtn = {
  width: 36, height: 36, borderRadius: 11, background: C.panel, border: `1px solid ${C.line}`,
  display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer",
};
