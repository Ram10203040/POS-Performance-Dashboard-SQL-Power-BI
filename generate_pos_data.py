"""
Synthetic Life Insurance POS dataset generator (3 months of requests).
Fixed seed => reproducible. Outputs CSVs + a MySQL load script.
Usage: python3 generate_pos_data.py
"""
import csv, random, os
from datetime import date, timedelta
from collections import Counter, defaultdict

random.seed(2026)
OUT = os.path.dirname(os.path.abspath(__file__))

START, END = date(2026, 7, 1), date(2026, 9, 30)      # request window
ASOF = END                                             # "today" for aging
PAY_START = date(2026, 4, 1)                           # payment window start
N_CUST, N_POL, N_REQ = 2000, 3000, 6000

def wchoice(d):
    return random.choices(list(d.keys()), weights=list(d.values()))[0]

# ---------- customers ----------
first = ["Amit","Priya","Rahul","Neha","Vikram","Anita","Suresh","Pooja","Rohit","Kavita","Manoj","Sneha","Arjun","Deepa",
 "Sanjay","Ritu","Karan","Meera","Ajay","Divya","Nikhil","Swati","Harish","Sunita","Vivek","Anjali","Rajesh","Shweta",
 "Mohit","Pallavi","Gaurav","Nisha","Tarun","Komal","Yash","Isha","Dinesh","Lata","Sachin","Rekha"]
last = ["Sharma","Verma","Singh","Gupta","Rao","Desai","Kumar","Mehta","Jain","Nair","Tiwari","Iyer","Reddy","Menon","Patel",
 "Agarwal","Malhotra","Pillai","Yadav","Bansal","Chopra","Joshi","Naidu","Das","Saxena","Kapoor","Bhatia","Mishra","Pandey","Sinha"]
cities = [("New Delhi","Delhi"),("Gurugram","Haryana"),("Noida","Uttar Pradesh"),("Mumbai","Maharashtra"),("Pune","Maharashtra"),
 ("Bengaluru","Karnataka"),("Hyderabad","Telangana"),("Chennai","Tamil Nadu"),("Kolkata","West Bengal"),("Jaipur","Rajasthan"),
 ("Lucknow","Uttar Pradesh"),("Ahmedabad","Gujarat"),("Chandigarh","Chandigarh"),("Indore","Madhya Pradesh"),("Bhopal","Madhya Pradesh"),
 ("Kochi","Kerala"),("Patna","Bihar"),("Nagpur","Maharashtra"),("Surat","Gujarat"),("Bhubaneswar","Odisha")]
customers = []
for i in range(1, N_CUST+1):
    c = random.choice(cities)
    dob = date(1950,1,1) + timedelta(days=random.randint(0, (date(2000,12,31)-date(1950,1,1)).days))
    customers.append([i, f"{random.choice(first)} {random.choice(last)}", dob.isoformat(), c[0], c[1]])

# ---------- policies ----------
plans = {"TERM01":(0.0025,0.006),"ENDOW02":(0.05,0.08),"ULIP03":(0.08,0.12),"PENS04":(0.04,0.07),"WLIFE05":(0.03,0.05)}
plan_w = {"TERM01":30,"ENDOW02":22,"ULIP03":18,"PENS04":10,"WLIFE05":20}
status_w = {"In Force":70,"Lapsed":12,"Paid-up":8,"Surrendered":5,"Matured":5}
mode_w = {"Monthly":25,"Quarterly":25,"Half-Yearly":20,"Yearly":30}
mode_div = {"Monthly":12,"Quarterly":4,"Half-Yearly":2,"Yearly":1}
policies = []
for i in range(1, N_POL+1):
    cust = i if i <= N_CUST else random.randint(1, N_CUST)
    plan = wchoice(plan_w); mode = wchoice(mode_w)
    sa = random.choice([500000,1000000,1500000,2500000,5000000,10000000])
    lo, hi = plans[plan]
    prem = round(sa*random.uniform(lo,hi)/mode_div[mode], 2)
    issue = date(2019,1,1) + timedelta(days=random.randint(0,(date(2026,6,30)-date(2019,1,1)).days))
    policies.append([f"LIC{100000+i}", cust, plan, wchoice(status_w), issue.isoformat(), f"{sa}.00", prem, mode])
pol = {p[0]: p for p in policies}
by_status = defaultdict(list)
for p in policies: by_status[p[3]].append(p[0])
non_inforce = [p for s in ("Lapsed","Paid-up","Surrendered","Matured") for p in by_status[s]]

# ---------- POS requests ----------
types = {"Contact Update":22,"Address Change":18,"Nominee Change":10,"Bank Mandate Update":12,"Duplicate Bond":8,
         "Premium Mode Change":8,"Policy Loan":8,"Surrender":7,"Revival":7}
channels = {"Branch":28,"Portal":22,"Mobile App":20,"Distributor":18,"Call Center":12}
chan_stp = {"Portal":0.70,"Mobile App":0.65,"Call Center":0.25,"Branch":0.12,"Distributor":0.10}
type_stp = {"Contact Update":1.0,"Address Change":0.9,"Duplicate Bond":1.0,"Bank Mandate Update":0.7,
            "Nominee Change":0.5,"Premium Mode Change":0.4,"Policy Loan":0,"Surrender":0,"Revival":0}
base_tat = {"Contact Update":2,"Address Change":3,"Nominee Change":4,"Bank Mandate Update":4,"Duplicate Bond":3,
            "Premium Mode Change":4,"Policy Loan":6,"Surrender":7,"Revival":10}
chan_tat = {"Distributor":1.3,"Branch":1.1,"Call Center":1.0,"Portal":0.9,"Mobile App":0.9}
month_bonus = {7:0.0, 8:0.06, 9:0.12}          # planted trend: STP improves each month
reasons = {"Incomplete documents":32,"Signature mismatch":24,"KYC pending":20,"Customer details mismatch":10}

days, wts = [], []
d = START
while d <= END:
    w = 1.0
    if d.weekday() == 5: w = 0.4
    if d.weekday() == 6: w = 0.1
    if d == date(2026,8,15): w = 0.05           # holiday
    if (d + timedelta(days=3)).month != d.month: w *= 1.6   # month-end spike
    if d.day <= 2: w *= 1.2
    w *= {7:1.0, 8:1.05, 9:1.10}[d.month]
    days.append(d); wts.append(w); d += timedelta(days=1)

raw = []
seen = set()
while len(raw) < N_REQ:
    t = wchoice(types); ch = wchoice(channels)
    rec = random.choices(days, weights=wts)[0]
    if t == "Revival":
        pn = random.choice(by_status["Lapsed"] if random.random() < 0.93 else by_status["In Force"])
    elif t == "Surrender":
        pn = random.choice(by_status["In Force"] if random.random() < 0.95 else non_inforce)
    else:
        pn = random.choice(by_status["In Force"] if random.random() < 0.96 else non_inforce)
    if (pn, t, rec) in seen:        # avoid accidental duplicates; planted ones are added later
        continue
    seen.add((pn, t, rec))
    pst = pol[pn][3]
    invalid = (t == "Revival" and pst != "Lapsed") or (t != "Revival" and pst != "In Force")
    reason = None; status = "Closed"
    if invalid and random.random() < 0.92:
        status, reason = "Rejected", "Policy not in force"
    elif random.random() < 0.05:
        status = "Rejected"
        rw = dict(reasons)
        if t == "Bank Mandate Update": rw["Invalid bank details"] = 40
        reason = wchoice(rw)
    if status == "Rejected":
        stp = "Y" if reason in ("Policy not in force","Invalid bank details") and random.random() < 0.5 else "N"
        tat = random.randint(0,1) if stp == "Y" else random.randint(1,3)
    else:
        p = min(0.95, chan_stp[ch]*type_stp[t] + (month_bonus[rec.month] if type_stp[t] > 0 else 0))
        stp = "Y" if random.random() < p else "N"
        if stp == "Y":
            tat = 0 if random.random() < 0.75 else 1
        else:
            b = base_tat[t]*chan_tat[ch]
            tat = max(1, round(random.gauss(b, b*0.35)))
    closed = rec + timedelta(days=tat)
    if closed > ASOF:                      # not yet closed as of 30-Sep
        status, closed, stp, reason = "Pending", None, "N", None
    raw.append([pn, t, ch, rec, closed, status, stp, reason])

raw.sort(key=lambda r: (r[3], r[0]))
requests = []
for i, r in enumerate(raw):
    requests.append([100001+i, r[0], r[1], r[2], r[3].isoformat(), r[4].isoformat() if r[4] else "", r[5], r[6], r[7] or ""])

# planted data-quality issues (answer key goes in README)
closed_idx = [i for i,r in enumerate(requests) if r[6]=="Closed" and r[4] < "2026-09-01"]
rej_idx = [i for i,r in enumerate(requests) if r[6]=="Rejected" and r[4] < "2026-09-01"]
random.shuffle(closed_idx); random.shuffle(rej_idx)
dq_missing_closed = [requests[i][0] for i in closed_idx[:6]]
for i in closed_idx[:6]: requests[i][5] = ""
dq_negative = [requests[i][0] for i in closed_idx[6:9]]
for i in closed_idx[6:9]:
    r = requests[i]; r[5] = (date.fromisoformat(r[4]) - timedelta(days=random.randint(1,2))).isoformat()
dq_no_reason = [requests[i][0] for i in rej_idx[:5]]
for i in rej_idx[:5]: requests[i][8] = ""
# duplicates (clean closed rows only)
used = set(closed_idx[:9])
cand = [i for i,r in enumerate(requests) if r[6]=="Closed" and i not in used and r[5]]
random.shuffle(cand)
dup_pairs = []
nid = requests[-1][0] + 1
for i in cand[:25]:
    r = requests[i][:]; r[0] = nid; requests.append(r); dup_pairs.append((requests[i][0], nid)); nid += 1

# ---------- premium payments ----------
def due_dates(p):
    issue = date.fromisoformat(p[4]); mode = p[7]; dd = min(issue.day, 28)
    out = []
    for y, m in [(2026,m) for m in range(4,10)]:
        k = m - issue.month
        ok = (mode=="Monthly") or (mode=="Quarterly" and k%3==0) or (mode=="Half-Yearly" and k%6==0) or (mode=="Yearly" and k%12==0)
        if ok:
            dt = date(y, m, dd)
            if dt > issue + timedelta(days=28): out.append(dt)
    return out
payments = []; pid = 900001
for p in policies:
    if p[3] not in ("In Force","Lapsed"): continue
    lapse = date(2026,4,1) + timedelta(days=random.randint(0,150)) if p[3]=="Lapsed" else None
    for dt in due_dates(p):
        if lapse:
            paid = None if dt > lapse else dt + timedelta(days=random.randint(-5,10))
        else:
            r = random.random()
            paid = None if r < 0.04 else (dt - timedelta(days=random.randint(0,5)) if r < 0.86 else dt + timedelta(days=random.randint(1,25)))
        if paid and paid > ASOF: paid = None
        payments.append([pid, p[0], dt.isoformat(), paid.isoformat() if paid else "", p[6]]); pid += 1

# ---------- write CSVs ----------
tables = {
 "customer": (["customer_id","name","dob","city","state"], customers),
 "policy": (["policy_no","customer_id","plan_code","status","issue_date","sum_assured","premium","premium_mode"], policies),
 "pos_request": (["request_id","policy_no","request_type","channel","received_date","closed_date","status","stp_flag","reject_reason"], requests),
 "premium_payment": (["payment_id","policy_no","due_date","paid_date","amount"], payments),
}
for name,(hdr,rows) in tables.items():
    with open(f"{OUT}/{name}.csv","w",newline="") as f:
        w = csv.writer(f); w.writerow(hdr); w.writerows(rows)

# ---------- MySQL script ----------
def lit(v, kind):
    if v == "" or v is None: return "NULL"
    if kind == "n": return str(v)
    return "'" + str(v).replace("'","''") + "'"
kinds = {"customer":"nsddd","policy":"sndsdnns","pos_request":"nssssddss","premium_payment":"nsddn"}
# simpler: numeric columns by position
numeric = {"customer":{0},"policy":{1,5,6},"pos_request":{0},"premium_payment":{0,4}}
sql = ["""-- Life Insurance POS practice database: 3 months of synthetic requests (MySQL 8.0+)
-- Run the whole file once. It drops and recreates the database insurance_pos_3m.
DROP DATABASE IF EXISTS insurance_pos_3m;
CREATE DATABASE insurance_pos_3m CHARACTER SET utf8mb4;
USE insurance_pos_3m;

CREATE TABLE customer (
  customer_id INT PRIMARY KEY,
  name        VARCHAR(100) NOT NULL,
  dob         DATE,
  city        VARCHAR(50),
  state       VARCHAR(50)
);
CREATE TABLE policy (
  policy_no     VARCHAR(15) PRIMARY KEY,
  customer_id   INT NOT NULL,
  plan_code     VARCHAR(20),
  status        VARCHAR(20),
  issue_date    DATE,
  sum_assured   DECIMAL(12,2),
  premium       DECIMAL(10,2),
  premium_mode  VARCHAR(15),
  FOREIGN KEY (customer_id) REFERENCES customer(customer_id)
);
CREATE TABLE pos_request (
  request_id     INT PRIMARY KEY,
  policy_no      VARCHAR(15) NOT NULL,
  request_type   VARCHAR(30),
  channel        VARCHAR(20),
  received_date  DATE,
  closed_date    DATE NULL,
  status         VARCHAR(15),
  stp_flag       CHAR(1),
  reject_reason  VARCHAR(50) NULL,
  FOREIGN KEY (policy_no) REFERENCES policy(policy_no)
);
CREATE TABLE premium_payment (
  payment_id  INT PRIMARY KEY,
  policy_no   VARCHAR(15) NOT NULL,
  due_date    DATE,
  paid_date   DATE NULL,
  amount      DECIMAL(10,2),
  FOREIGN KEY (policy_no) REFERENCES policy(policy_no)
);
CREATE INDEX idx_req_policy   ON pos_request(policy_no);
CREATE INDEX idx_req_received ON pos_request(received_date);
CREATE INDEX idx_req_type     ON pos_request(request_type);
CREATE INDEX idx_pay_policy   ON premium_payment(policy_no);
"""]
for name,(hdr,rows) in tables.items():
    for i in range(0, len(rows), 500):
        chunk = rows[i:i+500]
        vals = ",\n".join("(" + ",".join(lit(v, "n" if j in numeric[name] else "s") for j,v in enumerate(r)) + ")" for r in chunk)
        sql.append(f"INSERT INTO {name} ({','.join(hdr)}) VALUES\n{vals};\n")
sql.append("""-- Sanity check: expect the row counts listed in README.md
SELECT 'customer' AS tbl, COUNT(*) AS n FROM customer
UNION ALL SELECT 'policy', COUNT(*) FROM policy
UNION ALL SELECT 'pos_request', COUNT(*) FROM pos_request
UNION ALL SELECT 'premium_payment', COUNT(*) FROM premium_payment;
""")
open(f"{OUT}/create_and_load_pos_3m.sql","w").write("\n".join(sql))

# ---------- self-checks and stats ----------
cust_ids = {c[0] for c in customers}
assert all(p[1] in cust_ids for p in policies)
assert all(r[1] in pol for r in requests) and all(r[1] in pol for r in payments)
for r in requests:
    iss = pol[r[1]][4]; assert r[4] >= iss
bad = [r[0] for r in requests if r[5] and r[5] < r[4]]
assert set(bad) == set(dq_negative), (bad, dq_negative)
main = [r for r in requests if r[0] not in {b for _,b in dup_pairs}]
stats = {}
stats["counts"] = {k: len(v[1]) for k,v in tables.items()}
stats["status"] = Counter(r[6] for r in requests)
mon = defaultdict(lambda: [0,0])
for r in main:
    m = r[4][:7]; mon[m][0]+=1; mon[m][1]+= (r[7]=="Y")
stats["month"] = {m:(v[0], round(100*v[1]/v[0],1)) for m,v in sorted(mon.items())}
tt = defaultdict(list)
for r in main:
    if r[6]=="Closed" and r[5] and r[0] not in dq_negative:
        tt[r[2]].append((date.fromisoformat(r[5])-date.fromisoformat(r[4])).days)
stats["tat"] = {k: round(sum(v)/len(v),1) for k,v in sorted(tt.items())}
ch = defaultdict(lambda:[0,0])
for r in main: ch[r[3]][0]+=1; ch[r[3]][1]+=(r[7]=="Y")
stats["chan"] = {k:(v[0], round(100*v[1]/v[0],1)) for k,v in sorted(ch.items())}
rr = Counter(r[8] for r in main if r[8])
stats["rej"] = rr.most_common()
stats["unpaid"] = sum(1 for p in payments if p[3]=="")
stats["dup"]=len(dup_pairs)
stats["dq"]=(dq_missing_closed, dq_negative, dq_no_reason)
import json
print("Files written to:", OUT)
print(json.dumps(stats, default=str, indent=1))
