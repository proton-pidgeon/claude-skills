---
name: deep-research
description: Produce a comprehensive, long-form research report from public sources, structured as a formal analytic brief with a one-sentence summary, BLUF, background, findings, analysis with confidence scores, conclusions, and numbered references. The defining move is disconfirmation. Popular opinion from social media and news is treated as claims to be tested against academic and official data-backed sources, then the report states plainly whether the data busts or confirms the popular view. Use this skill whenever the user says to research a topic, asks for a deep dive, a research report, or a briefing, wants something thoroughly researched, or wants public sentiment fact-checked against the evidence, even if they do not use the word report.
---

# Deep Research

Produce a rigorous, long-form research report grounded entirely in verifiable public sources. The output is a single Markdown document, always delivered as a Claude artifact, written in the style of a formal analytic brief. The work is not a summary of search results — it is an investigation that actively pits popular belief against data-backed evidence and reports the result.

## What makes this skill different

Most "research" collapses into restating the consensus of the top search hits. This skill does the opposite: it identifies what people *believe* (from social media and news sentiment) and then works hard to disconfirm those beliefs using higher-quality, data-backed sources. The deliverable's value is in the gap between perception and evidence — the myths busted and the beliefs confirmed.

## Workflow

### 1. Frame the question
Restate the topic as a precise research question. Identify the specific claims, popular beliefs, or points of contention to investigate. If the topic is broad, decompose it into 3–6 sub-questions and tell the user the framing before diving in — a one-line confirmation is enough, don't stall.

### 2. Gather popular sentiment (the claims to test)
Search news coverage and social media discourse to capture what people currently believe and assert about the topic. Note the prevailing narratives, common assertions, and emotional tenor. These are not yet findings — they are hypotheses to be tested. Capture a few representative examples.

### 3. Gather data-backed evidence (the test)
Find authoritative sources to evaluate those claims against. Source quality hierarchy, strongest first:
1. Peer-reviewed academic research and meta-analyses
2. Official studies and datasets backed by research data (government statistical agencies, regulators, international bodies, primary institutional reports)
3. Original reporting from reputable outlets that cite primary data
4. News and social sentiment — used only as the *subject* of analysis, never as proof of a factual claim

**Source floor: at least 12 distinct, verified sources.** More for contested or broad topics. Favor primary and original sources over aggregators. When sources conflict, surface the conflict explicitly — never average disagreeing sources into a false middle.

### 4. Verify every reference
Every URL in the References section must be confirmed reachable and must actually contain the cited content during this research session — fetch or search-confirm it. Never cite a URL recalled from memory, guessed, or pattern-constructed. If a source can't be verified to a live public URL, it does not go in the report. Broken or paywalled-without-public-version links are dropped.

### 5. Adjudicate: bust or confirm
For each major popular claim, state plainly whether the data-backed evidence **busts**, **confirms**, **partially confirms**, or is **inconclusive** about it, and why. This is the heart of the report.

### 6. Score confidence
Assign every major finding a confidence level using the rubric below, and show the reasoning briefly.

### 7. Write the report
Follow the exact structure in the next section. Always deliver the finished report as a **Claude artifact** (a Markdown artifact), not as inline chat text or a loose file — create it with the artifact/file-creation tool so it renders as a saved, reusable document the user can view, edit, and download. Give the artifact a descriptive title matching the report title.

## Confidence scoring rubric

Score each major finding 1–5. Base the score on four factors: source quality, corroboration across independent sources, recency/currency, and directness of evidence (does the source measure the thing, or only imply it?).

| Score | Label | Criteria |
|-------|-------|----------|
| 5 | Very High | Multiple independent peer-reviewed or official data sources agree; direct measurement; current. |
| 4 | High | Strong data-backed sources agree; minor gaps in recency or directness. |
| 3 | Moderate | Reasonable evidence but limited corroboration, mixed findings, or some reliance on secondary sources. |
| 2 | Low | Sparse, dated, indirect, or contested evidence; data-backed support is thin. |
| 1 | Very Low | Largely anecdotal or sentiment-driven; little to no data-backed support. |

Always state confidence as `[Label, N/5]` and name the limiting factor (e.g. "Moderate, 3/5 — only one primary dataset, not yet replicated").

## Report structure

ALWAYS produce the report as a single Markdown **Claude artifact** using this exact structure and order:

```markdown
# [Descriptive Report Title]

> **In one sentence:** [Ultra-micro summary — a single sentence capturing the core takeaway.]

## BLUF
[Bottom Line Up Front. 3–5 sentences maximum. The most decision-relevant conclusions, including the headline myth-busts or confirmations. No throat-clearing.]

## Background
[Context a reader needs to understand the topic: what it is, why it matters, the state of the discourse, and the popular beliefs/claims this report tests. Cite as you go [1][2].]

## Findings
[The evidence, organized by sub-question or claim. For each major claim:
- State the popular belief.
- Present the data-backed evidence.
- Adjudicate: **Busts / Confirms / Partially confirms / Inconclusive**.
- Give the confidence score.
Cite every factual statement with sequential in-text markers.]

## Analysis
[Synthesis across findings. Include counterpoints and genuine disagreements between sources — do not flatten them. Explain why sources diverge where they do. Discuss limitations of the evidence base. Surface what would change the conclusions.]

## Conclusions
[What the investigation establishes, what remains uncertain, and the net verdict on the popular narrative. Forward-looking notes or open questions where relevant.]

## References
[Numbered list, sequential, in order of first in-text appearance. Each entry: title + verified public URL. Format:
1. [Source Title — Publisher/Author](https://verified-url)
]
```

## Citation rules

- In-text citations are bare bracketed numbers: `[1]`, `[2]`, `[3]`.
- Numbering is **sequential in order of first appearance** in the document body. The first source cited is `[1]`, the next new source is `[2]`, and so on.
- Reuse the same number when re-citing a source already introduced.
- Multiple sources for one claim: `[3][7]`.
- The References section lists sources in that same numeric order.
- Every reference number used in-text must appear in References, and vice versa — no orphans.

## Quality bar before delivering

Check all of these before presenting the report:
- [ ] One-sentence summary, BLUF (≤5 sentences), and all six sections present and in order.
- [ ] At least 12 distinct verified sources.
- [ ] Every major popular claim explicitly adjudicated (bust/confirm/partial/inconclusive).
- [ ] Every major finding carries a `[Label, N/5]` confidence score with its limiting factor.
- [ ] Counterpoints and source disagreements are represented, not smoothed over.
- [ ] Every in-text number resolves to a verified live URL in References; no orphans, no guessed links.
- [ ] Delivered as a Markdown Claude artifact (not inline chat text), with a descriptive title.

## Notes

- Long-form means thorough, not padded. Depth comes from evidence and adjudication, not word count. Cut filler.
- If the evidence is genuinely thin, say so plainly and score it low — a low-confidence honest finding beats false certainty.
- Stay neutral on contested political/values questions: report what the data shows and where reasonable people disagree, rather than picking a side.
