# VPC Flow Logs — Download & Validation Guide (IBM COS, single-site `sao01`)

This guide documents the working procedure to download VPC flow log objects from an
IBM Cloud Object Storage (COS) bucket and validate that flow data is being collected.

It uses only `ibmcloud` (for the IAM token), `curl`, `python3` (standard library) and `gunzip`.
No SDKs, API keys or HMAC credentials are required.

---

## Background — why the previous attempts failed

| Attempt | Result | Actual cause |
|---|---|---|
| `ibmcloud cos object-get ... --output file` | `Invalid output format` | `--output` sets the CLI format (json/text); the destination file is a positional argument. |
| `ibmcloud cos object-get ... OUTFILE` | `bucket not found` | Region/endpoint config differed from the command that successfully listed objects. |
| `curl` with keys copied from `ibmcloud cos objects` | `NoSuchKey` | Keys were copied/typed by hand from a listing that may show encoded or modified keys, so the requested key did not match the stored one. |

**Key takeaway:** object keys contain CRNs (`:`) and many `/` levels. Never build keys by hand.
List the bucket through the S3 API (keys come back exactly as stored) and URL-encode each key
**once**, preserving `/`.

---

## Reference

| Item | Value |
|---|---|
| COS instance | `cos-vpc-flow-logs-central` |
| COS instance ID | `29235d8c-3d29-4932-870c-7ce8db373704` |
| Bucket (br-sao) | `vpc-flow-logs-test-br-sao` |
| Endpoint (sao01) | `https://s3.sao01.cloud-object-storage.appdomain.cloud` |
| Bucket (us-south) | `vpc-flow-logs-test-us-south` |
| Endpoint (sjc04) | `https://s3.sjc04.cloud-object-storage.appdomain.cloud` |

Example object key (raw, as stored):

```
ibm_vpc_flowlogs_v1/account=<account>/region=br-sao/vpc-id=crn:v1:bluemix:public:is:br-sao:a/<account>::vpc:<vpc-id>/subnet-id=crn:.../endpoint-type=vnics/instance-id=crn:.../vnic-id=<vnic-id>/record-type=egress/year=2026/month=09/day=16/hour=17/stream-id=20260916T173449Z/00000000.gz
```

---

## Prerequisites

- Logged in to IBM Cloud in the terminal (`ibmcloud login`).
- Your user has **Content Reader** (or **Reader**) access on the bucket / COS instance.
- `curl`, `python3` and `gunzip` available.

All commands below must run **in the same terminal session** (they share shell variables).

---

## Step 1 — Set variables and get the IAM token

```bash
BUCKET="vpc-flow-logs-test-br-sao"
EP="https://s3.sao01.cloud-object-storage.appdomain.cloud"
TOKEN=$(ibmcloud iam oauth-tokens --output json | python3 -c 'import json,sys; print(json.load(sys.stdin)["iam_token"])')
mkdir -p ~/flowlogs && cd ~/flowlogs
```

> The token already includes the `Bearer ` prefix and is valid for about 1 hour.
> If you get HTTP 401/403 later, re-run the `TOKEN=` line.

For the us-south bucket, change `BUCKET` and `EP` to the values in the reference table.

---

## Step 2 — List the exact object keys

```bash
curl -s -H "Authorization: $TOKEN" "$EP/$BUCKET?list-type=2" \
| python3 -c 'import sys,xml.etree.ElementTree as ET; [print(k.text) for k in ET.fromstring(sys.stdin.read()).iter() if k.tag.endswith("}Key")]' \
> keys.txt

wc -l keys.txt
```

The API returns up to 1,000 keys per request, which covers this bucket.

### Note on object count

The count grows over time because the flow log collector keeps writing new objects
(e.g. 46 objects at first check, 76 later). To confirm the growth is legitimate:

```bash
# Objects per hour — newer hours explain the extra objects
grep -o 'year=[0-9]*/month=[0-9]*/day=[0-9]*/hour=[0-9]*' keys.txt | sort | uniq -c

# No duplicate keys (should equal the total from wc -l)
sort -u keys.txt | wc -l
```

---

## Step 3 — Download all objects

```bash
i=0
while IFS= read -r key; do
  enc=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe="/"))' "$key")
  out=$(printf "%04d.gz" $i)
  curl -sfg -H "Authorization: $TOKEN" -o "$out" "$EP/$BUCKET/$enc" \
    && echo "$out  $key" >> manifest.txt \
    || echo "FAILED: $key"
  i=$((i+1))
done < keys.txt

ls *.gz | wc -l
```

Details:

- Each key is URL-encoded exactly once (`:` → `%3A`, `=` → `%3D`, `/` preserved); COS decodes it back to the stored key.
- `-g` disables curl URL globbing, `-f` makes HTTP errors count as failures.
- Files are saved with short local names (`0000.gz`, `0001.gz`, …) because raw keys contain `:` and deep paths.
- `manifest.txt` maps each local file to its original key (VNIC, direction, date/hour).

The number of `.gz` files should match the line count of `keys.txt`, with no `FAILED` lines.

---

## Step 4 — Validate file integrity

```bash
# No output = all archives are valid
for f in *.gz; do gunzip -t "$f" || echo "corrupted: $f"; done

# Inspect the first file
gunzip -c 0000.gz | python3 -m json.tool | head -60

# Records per file
for f in *.gz; do
  gunzip -c "$f" | python3 -c 'import json,sys; d=json.load(sys.stdin); r=d.get("flow_logs",[]); print(sys.argv[1], "records:", len(r), "| fields:", list(r[0].keys()) if r else list(d.keys()))' "$f"
done
```

---

## Step 5 — Sample the flow log data

### 5.1 Overall summary

```bash
python3 - <<'EOF'
import gzip, json, glob
files = sorted(glob.glob("*.gz"))
total, empty, vnics, dirs, start, end = 0, 0, set(), {}, [], []
for f in files:
    d = json.loads(gzip.decompress(open(f,"rb").read()))
    r = d.get("flow_logs", [])
    total += len(r)
    if not r: empty += 1
    vnics.add(d.get("network_interface_id"))
    if d.get("capture_start_time"): start.append(d["capture_start_time"])
    if d.get("capture_end_time"): end.append(d["capture_end_time"])
    for x in r:
        k = f'{x.get("direction")}/{x.get("action")}'
        dirs[k] = dirs.get(k, 0) + 1
print(f"Files: {len(files)} | with records: {len(files)-empty} | empty: {empty}")
print(f"Total flow records: {total}")
print(f"Distinct VNICs: {len(vnics)}")
print(f"Capture window: {min(start) if start else '?'}  ->  {max(end) if end else '?'}")
print("Direction/action:", dirs)
EOF
```

### 5.2 Random sample of 15 records

```bash
python3 - <<'EOF'
import gzip, json, glob, random
recs = []
for f in glob.glob("*.gz"):
    for x in json.loads(gzip.decompress(open(f,"rb").read())).get("flow_logs", []):
        recs.append((f, x))
sample = random.sample(recs, min(15, len(recs)))
print(f'{"file":8} {"start":20} {"dir":8} {"action":8} {"proto":5} {"source":22} {"destination":22} {"bytes":>8}')
for f, x in sample:
    src = f'{x.get("initiator_ip")}:{x.get("initiator_port","")}'
    dst = f'{x.get("target_ip")}:{x.get("target_port","")}'
    b = (x.get("bytes_from_initiator") or 0) + (x.get("bytes_from_target") or 0)
    print(f'{f[:8]:8} {str(x.get("start_time",""))[:19]:20} {str(x.get("direction")):8} {str(x.get("action")):8} {str(x.get("transport_protocol")):5} {src:22} {dst:22} {b:>8}')
EOF
```

### 5.3 One full record (all fields)

```bash
gunzip -c $(for f in *.gz; do gunzip -c "$f" | grep -q '"initiator_ip"' && echo "$f" && break; done) \
| python3 -c 'import json,sys; d=json.load(sys.stdin); r=d.pop("flow_logs"); print(json.dumps(d,indent=2)); print("--- first record ---"); print(json.dumps(r[0],indent=2))'
```

---

## Validation checklist

Flow logs are being collected correctly when:

- [ ] Object count in `keys.txt` matches the number of downloaded `.gz` files, with no `FAILED` lines.
- [ ] `gunzip -t` reports no corrupted archives.
- [ ] Total flow records (Step 5.1) is greater than zero.
- [ ] The capture window matches the period the collector has been active.
- [ ] Source/destination IPs in the sample belong to your subnets / VSIs.
- [ ] `action` shows `accepted` (and `rejected` if security groups or ACLs block traffic).

Some empty files are normal: they represent capture windows with no traffic on that VNIC.
It is only a problem if **all** files are empty.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| HTTP 401 / 403 | Token expired — re-run the `TOKEN=` line. If it persists, grant **Content Reader** on the bucket. |
| `NoSuchBucket` | Wrong endpoint for the bucket location (check `EP`). |
| `NoSuchKey` | Key was modified — always use keys from `keys.txt`, never copy them by hand. |
| Object count changed | Expected — the collector writes new objects continuously (see Step 2 note). |
