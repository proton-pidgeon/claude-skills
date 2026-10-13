#!/usr/bin/env python3
"""Validate a book review draft against the book-review skill's rules.

Standard library only. If pyspellchecker is installed, unknown words are also flagged.

Usage:
  check_review.py REVIEW.md --errors N [--spoilers FILE] [--lang en]
                  [--author-gender-confirmed]

Exit code 0 when there are no FAILs, 1 otherwise.
"""
import argparse
import re
import sys

NUM_WORDS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5}
RATING_PATTERNS = [
    r"\b([1-5])(?:\.0)?\s*(?:out of|/)\s*(?:5|five)\b",
    r"\b(one|two|three|four|five)\s+out of\s+(?:5|five)\b",
    r"\b([1-5])\s+(?:of|out of)\s+(?:5|five)\s+stars?\b",
]
EDITING_TERMS = [
    "typo", "error-free", "error free", "flawless", "proofread", "edited",
    "editing", "no errors", "not a single error", "grammatical error",
    "spelling error", "mistake",
]
PRONOUNS = r"\b(he|she|him|her|his|hers|himself|herself)\b"
PAGE_COUNT = r"\b\d[\d,]*\s*(?:-\s*)?(?:pages?|pp\.?)\b|\bpage count\b|\bpages long\b"

fails, warns = [], []


def fail(msg):
    fails.append(msg)


def warn(msg):
    warns.append(msg)


def sentences(text):
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+", text) if s.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("review")
    ap.add_argument("--errors", type=int, required=True,
                    help="number of definite editing errors found in the book")
    ap.add_argument("--spoilers", help="file of spoiler names/terms, one per line")
    ap.add_argument("--lang", default="en", help="two-letter language code of the book")
    ap.add_argument("--author-gender-confirmed", action="store_true")
    a = ap.parse_args()

    text = open(a.review, encoding="utf-8").read()
    body = re.sub(r"^#.*$", "", text, flags=re.M)  # ignore markdown headings for counts
    lower = body.lower()
    english = a.lang.lower().startswith("en")

    # Word count
    words = re.findall(r"[^\W_]+(?:['’-][^\W_]+)*", body)
    if len(words) < 300:
        fail(f"Review is {len(words)} words; the minimum is 300.")

    # Rating
    ratings = set()
    for pat in RATING_PATTERNS:
        for m in re.finditer(pat, lower):
            g = m.group(1)
            ratings.add(NUM_WORDS.get(g, None) or int(g))
    if english:
        if not ratings:
            fail("No rating found (expected something like '3 out of 5').")
        elif len(ratings) > 1:
            warn(f"Several different ratings appear: {sorted(ratings)}. Make sure the final one is unambiguous.")
    else:
        if not ratings and not re.search(r"\b[1-5]\s*/\s*5\b", lower):
            warn("No rating detected by pattern. Confirm the review states a 1 to 5 rating in its language.")
    rating = max(ratings) if len(ratings) == 1 else None

    # Editing thresholds
    if a.errors >= 10 and 5 in ratings:
        fail(f"{a.errors} definite errors were found, so the rating cannot be 5 out of 5.")
    if a.errors == 0:
        if english:
            if not any(t in lower for t in EDITING_TERMS):
                fail("Zero errors were found, so the review must explicitly praise the flawless editing.")
        else:
            warn("Zero errors were found. Confirm the review praises the flawless editing.")

    # Page counts
    if english:
        for m in re.finditer(PAGE_COUNT, lower):
            fail(f"Possible page-count mention: '{m.group(0)}'. Use an approximate word count instead.")

    # Dashes
    for ch, name in (("—", "em dash"), ("–", "en dash")):
        n = text.count(ch)
        if n:
            fail(f"{n} {name}(es) found. Rewrite with commas, colons, parentheses, or separate sentences.")
    if re.search(r"\s--\s", text):
        fail("Double hyphen used as a dash. Rewrite the sentence.")

    # Pronouns
    if english and not a.author_gender_confirmed:
        hits = [s for s in sentences(body) if re.search(PRONOUNS, s, re.I)]
        for s in hits:
            warn(f"Gendered pronoun (fine if it refers to a character, not the author): {s[:160]}")

    # Spoilers
    if a.spoilers:
        terms = [t.strip() for t in open(a.spoilers, encoding="utf-8") if t.strip() and not t.startswith("#")]
        for t in terms:
            if re.search(r"(?<!\w)" + re.escape(t.lower()) + r"(?!\w)", lower):
                fail(f"Spoiler-ledger term appears in the review: '{t}'.")
    else:
        warn("No spoiler file given. Check the draft against the spoiler ledger by hand.")
    for hint in ("plot twist", "the ending", "twist at the end", "won't see it coming",
                 "never guess", "not everyone survives", "final reveal", "shocking ending"):
        if hint in lower:
            warn(f"Phrase that may hint at a spoiler: '{hint}'.")

    # Mechanical proofreading
    for m in re.finditer(r"\b(\w+)\s+\1\b", body, re.I):
        if m.group(1).lower() not in ("had", "that"):
            fail(f"Repeated word: '{m.group(0)}'.")
    if re.search(r"[^\S\n]{2,}", text):
        warn("Double spaces found.")
    if re.search(r"\s[,.;:!?]", text):
        warn("Space before punctuation found.")
    if english:
        try:
            from spellchecker import SpellChecker  # type: ignore
            sp = SpellChecker()
            unknown = sorted(w for w in sp.unknown(w.lower() for w in words) if w.isalpha())
            if unknown:
                warn("Words not in the spelling dictionary (names are expected here): " + ", ".join(unknown[:60]))
        except ImportError:
            warn("pyspellchecker not installed, so no dictionary spelling check ran. Proofread manually.")

    # Report
    print(f"Words: {len(words)}  Rating detected: {rating if rating else sorted(ratings) or 'none'}  "
          f"Definite book errors: {a.errors}")
    for m in fails:
        print("FAIL  " + m)
    for m in warns:
        print("WARN  " + m)
    print("""
Manual checklist (every answer must be yes):
  [ ] The review is written in the same language as the book.
  [ ] The rating matches the evidence in the notes, and was not rounded up to be kind.
  [ ] Each deducted star has a stated reason, or a 5 is thoroughly justified.
  [ ] Negatives are listed, or the review explicitly says there are none.
  [ ] Nothing past the premise boundary appears, including hints, checked line by line against the ledger.
  [ ] Every factual claim was verified in the text or is certain. Opinions read as opinions.
  [ ] The author is referred to neutrally unless gender is confirmed in the notes.
  [ ] The draft was reread in full at least twice.""")
    print("\nRESULT: " + ("FAIL" if fails else "PASS (review the warnings)"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
