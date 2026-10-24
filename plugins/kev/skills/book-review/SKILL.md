---
name: book-review
description: Read a whole book and write an honest, spoiler-free, rule-checked review with a 1 to 5 rating, an error log, and a spoiler ledger. Use when Kev asks to review a book, write a book review, rate a book, or draft a review of a title or book file.
---

# Book review

Read the full text of a book, keep working notes while reading (an editing-error
log, a spoiler ledger, and evidence for strengths and weaknesses), decide an
honest rating, draft the review, and validate the draft against the review
rules before handing it over.

The rules below are hard requirements. The review is only useful if readers can
trust it, so honesty and accuracy outrank everything else, including making the
review sound good.

## The review rules

1. **Honest.** The rating and tone follow the evidence. A book that was a slog
   gets a low rating and a generally negative review. Never inflate.
2. **Correct spelling and grammar,** proofread repeatedly.
3. **Same language as the book.** A Spanish book gets a Spanish review.
4. **At least 300 words.** Aim for 400 to 600.
5. **No spoilers at all** (see "What counts as a spoiler").
6. **A rating on a 1 to 5 scale stated in the review,** where 1 is the worst and
   5 is the best (for example, "I rate this book 3 out of 5 stars.").
7. **The rating is explained.** For anything under 5, say why each deducted star
   was deducted. For a 5, explain thoroughly why the book earns it.
8. **Negatives are listed,** meaning what could change to make the book better.
   If there is truly nothing to criticize, say so explicitly in your own words.
9. **Ten or more definite editing errors, or signs the book was not
   professionally edited, means no 5 out of 5.**
10. **Zero editing errors found means the review must explicitly praise the
    flawless editing,** in your own words. This is rare, so double-check the
    error log before claiming it.
11. **One to nine errors** need not be mentioned (it is allowed).
12. **No page count.** Page counts vary by format. If length deserves mention,
    give the word count instead.
13. **No author gender** unless it is certain. Default to "the author" or the
    author's name.
14. **No objectively false statements, and nothing uncertain presented as
    certain.** Rules 12 and 13 are specific cases of this broader rule.

## Step 0. Settle inputs

Before reading, find out two things. Ask in one short question (AskUserQuestion
if available). If no one is there to answer, proceed with the defaults and say
which you used at the top of the reply.

- **Which book and where the text is.** Default to the search order in Step 1.
- **Whose verdict leads.** If Kev has read the book and gives his rating or
  reactions, those lead: the review must not contradict his verdict, and you
  build the evidence around it (but flag it plainly if the text contradicts one
  of his factual claims). If he gives nothing, form your own honest assessment
  from the full text and state in the reply that the rating is yours.

## Step 1. Get the complete text

The rules assume the reviewer finished the book, so the review must rest on the
**entire text**. Never review from memory of the book, plot summaries, other
reviews, or web search. If the complete text cannot be obtained, stop and say
so.

Look for the text in this order:

1. A file attached to the conversation or a path Kev gave.
2. Kev's OneDrive Books folder. In cloud sessions use the Pinakes MCP tools
   (`search`, then `get_document`). On the Mac Studio, the local path is
   `~/Library/CloudStorage/OneDrive-Personal/Documents/Books`. On Windows hosts
   it is `%USERPROFILE%\OneDrive\Documents\Books`.
3. The Fovea library, through the `fovea-export` skill, when the `fovea` tools
   are available.

Convert the book to plain text if needed (PDF, EPUB, and DOCX all work). If a
document is large, page through it in full rather than sampling. Partial reading
is not acceptable.

Keep a complete plain-text copy of the book in the working directory
(`book-<slug>.txt`). When reading through Pinakes, write each page to that file
as you read it. The fact check in Step 8 needs it, because search tools return
one hit per document and cannot count how often something appears.

## Step 2. Prepare

Record these in the notes file (`review-notes-<slug>.md`) before the read-through.

- **Language** of the book. The review will be written in it.
- **Word count.** Count the words of the main text, excluding front matter
  (copyright page, contents, acknowledgments) and back matter (author bio,
  previews of other books). This is an estimate, so it may only appear in the
  review as an approximation, for example "roughly 85,000 words."
- **Author gender evidence.** Note it only if the text itself states it plainly
  (for example, an "About the Author" section that uses pronouns for the
  author). Otherwise record "unconfirmed," which means neutral references only.
- **Premise boundary.** Mark where the setup ends, usually around the first 10
  to 15 percent of the book, or the point the jacket copy would describe. Only
  material before this boundary may appear in the review.

## Step 3. Read the whole book and take notes

Read chapter by chapter. For long books you may fan out chunks to subagents
with these same instructions, then merge their notes. For each chunk, add to
the notes file:

**Error log.** Log one error per line, in this exact format. Do not use a
table.

```
"example" (context) - chapter no. - error type
```

- **"example"** is the exact text as it appears in the book.
- **(context)** says briefly where it occurs (who is speaking or what is
  happening) and, when it helps, what the text should say.
- **chapter no.** is the chapter, written as "Ch. 3," or "Front matter" for
  the front matter.
- **error type** is one of: spelling, grammar, punctuation, wrong word, missing
  word, hyphenation, pronoun error, name inconsistency, or continuity.

For example:

```
"pouring over the files" (Sam rereads the case files on the plane; should be "poring") - Ch. 3 - wrong word
```

Keep two lists under separate headings in the notes file. "Error log
(definite, authorial)" holds the errors that count. "Excluded" holds the
items that do not count, in the same format, with the reason for excluding
it as the error type (for example, "OCR artifact" or "intentional dialect").
Order each list by chapter.

- Count only definite errors made by the author or editor.
- Put in the excluded list, and do not count, anything that is probably a
  file-conversion artifact (OCR misreads, broken hyphenation at line ends,
  stray markup, mangled ligatures, missing spaces around formatting),
  intentional dialect or voice, deliberate stylistic choices, and legitimate
  regional spelling (British versus American).
- When unsure whether something is an error, put it in the excluded list and
  say why in the context.

**Spoiler ledger.** Every twist, reveal, character death or fate, hidden
identity, ending, late-book development, and resolution of a central question.
This list is what the draft gets checked against. Include the specific names
and terms that would give these away.

**Strengths and weaknesses.** Each with concrete evidence (a scene, a pattern,
a passage reference) so the review's claims can be backed up. Look at prose,
pacing, structure, characterization, argument quality (for nonfiction), accuracy
(for nonfiction), dialogue, worldbuilding, and whether the book delivers on what
it sets out to do.

## Step 4. Decide the rating

1. Start from the evidence (and Kev's verdict, if he gave one).
2. Count the lines in the definite error log. If there are 10 or more, or the
   book shows other signs of not being professionally edited (inconsistent
   formatting, repeated continuity errors, unedited filler), the rating cannot
   be 5.
3. Write down, in the notes, the reason for each star deducted, or the case for
   a 5. These reasons go into the review.

Be willing to give a 1 or a 2. Do not round up to be kind.

## What counts as a spoiler

Anything past the premise boundary. That includes outcomes, twists, reveals,
deaths, who did it, who ends up with whom, how the central conflict resolves,
late plot developments, and the ending. It also includes hints at them, such as
"the twist in the final act changes everything," "not everyone survives," or
"you'll never guess who is behind it." For nonfiction, the book's core argument
and conclusions are fair to discuss, but surprising late revelations in a
narrative nonfiction book are not.

When in doubt, leave it out.

## Step 5. Draft the review

Write in the book's language. When the book is in English, use US English
spelling.

A structure that works well (as flowing prose, not headings, unless Kev asks for
headings):

1. What the book is: genre, the premise as set up before the boundary, and the
   kind of reader it is aimed at.
2. What works, with specific evidence.
3. What does not work, or what could be better (rule 8). If there is genuinely
   nothing, say so plainly.
4. Editing. Required when zero errors were found (rule 10), and appropriate
   when there are many.
5. The rating, stated as "X out of 5," with the reason for each deducted star
   or the case for a perfect score.
6. Who would enjoy it, and who might not.

Do not include content warnings or "readers should know" notes about violence,
language, sexual content, or other sensitive material. Kev does not want them
in his reviews. Describing the genre and tone as part of the premise is fine,
but do not single out content as a caution to readers.

Style requirements:

- Plain, direct prose. No ornamental phrasing or clever aphorisms.
- No em dashes or en dashes. Use commas, colons, parentheses, or separate
  sentences.
- No abrupt colon-fragment lead-ins such as "The verdict:" and no semicolons
  splicing two short clauses. Write full sentences with natural connectives.
- Keep articles and conjunctions. Do not write in clipped fragments.

Factual discipline:

- Every factual statement must be something you verified in the text or know
  for certain. Do not state publication year, series order, the author's
  background, awards, or sales unless you have confirmed them. When in doubt,
  leave it out or phrase it as your impression ("it reads like," "I found").
- Opinions are fine and expected, as long as they read as opinions.
- No page counts. Word count only as an approximation, and only if it matters.
- Neutral references to the author unless gender is confirmed in the notes.

## Step 6. Proofread and validate

Repeat until everything passes.

1. Save the draft to `review-<slug>.md` (the review text only, with no notes).
2. Run the checker, which is in this skill's folder at `scripts/check_review.py`:

   ```bash
   python3 <skill-dir>/scripts/check_review.py review-<slug>.md \
     --errors <definite error count> \
     --spoilers spoilers-<slug>.txt \
     --lang <two-letter language code> \
     [--author-gender-confirmed]
   ```

   `spoilers-<slug>.txt` holds the key names and terms from the spoiler ledger,
   one per line. The script needs only the Python standard library. If
   `pyspellchecker` is installed it also flags unknown words.

3. Fix every FAIL. Review every WARN by hand (pronoun warnings often refer to
   characters, which is fine).
4. Reread the full draft at least twice yourself, once for spelling and grammar
   and once for facts and spoilers, comparing it against the spoiler ledger
   line by line.
5. Answer the manual checklist the script prints. Every answer must be yes.

## Step 7. Reflect against the rules

The checker catches mechanical problems. This step catches the subtler ones.
Reread the draft once more, slowly, as a skeptical reader holding the 14 rules,
and ask each of these questions. Fix whatever they turn up, then rerun the
checker.

1. **Can every quoted error be wrong in the source?** If the text came from OCR
   or another conversion, a missing word, a dropped letter, or odd spacing
   could be a scanning glitch. In the review, quote only errors that a
   conversion cannot produce, such as wrong words ("pouring" for "poring"),
   grammar mistakes, and name inconsistencies. Keep the uncertain ones in the
   notes.
2. **Is every intensifier supported by the text?** Words like "at a glance,"
   "never," "always," "every," and "strong" make claims. Check each one against
   the book, and soften it to what the text actually shows.
3. **Did a content warning slip in?** Remove any "readers should know" note
   about violence, language, sexual content, or other sensitive material
   (see Step 5).
4. **Does any aside give away a development?** Side remarks can spoil as
   easily as plot summary. A passing mention that a relationship "heats up,"
   or that a character "won't be the same," reveals what happens. Cut or
   generalize anything that hints at events past the premise boundary.
5. **Whose experience do the first-person lines describe?** Lines such as "I
   couldn't put it down" claim a reading experience. If Kev gave his own
   verdict and reactions, make sure the lines match them. If the rating is
   yours because Kev has not read the book, say so plainly in the reply. Point
   out that the experiential lines describe your reading, and that the rules
   assume the reviewer finished the book, so he should read it, or tell you
   his reactions, before posting it under his name.

Record what the reflection changed in the notes file, under a "Reflection"
heading. Report it briefly in the reply, too.

## Step 8. Fact-check against the source text

The review must contain nothing that is not in the book. Check it against the
book text itself, not against memory or the notes, because notes can carry an
earlier mistake forward.

1. **List every checkable claim.** Go sentence by sentence and pull out each
   statement of fact. That includes names, roles, places, and relationships,
   descriptions of the premise and setting, every quoted phrase or error,
   every number (victims, word count, dates), and every claim about how often
   something happens ("again and again," "several," "often").
2. **Verify each claim in `book-<slug>.txt`.** Search the full text for each
   one. Confirm that quoted phrases appear exactly as quoted. For frequency
   claims, count the occurrences (for example with `grep -c`) and judge
   whether the count supports the wording. A habit that appears four times in
   a whole novel does not appear "so often."
3. **Fix what fails.** Remove or reword any claim the text does not support.
   Soften anything only partly supported. Opinions ("I found the pacing
   quick") don't need text evidence, but any facts inside them do.
4. **Record the result.** Add a "Fact check" table to the notes file, with one
   row per claim, the evidence (chapter and a short quote or count), and the
   result (verified, softened, or removed).
5. **Rerun the checker** if anything changed.

Report in the reply how many claims were checked and what the fact check
changed.

## Step 9. Save next to the book

Always save both `review-<slug>.md` (the review only) and
`review-notes-<slug>.md` (error log, excluded artifacts, spoiler ledger,
evidence, and rating reasons) in the same folder as the book file. Do this
without being asked. A copy that exists only in the session workspace does not
count as saved.

- **Book read from OneDrive through Pinakes:** write both files with the
  Pinakes `create_document` tool to the book's folder (for example
  `Documents/Books/<Title>/review-<slug>.md`). If a file already exists there,
  replace it with `update_document`.
- **Book read from a local path** (Mac Studio or Windows OneDrive folder, or any
  other folder Kev named): write both files into that same directory.
- **Book exported from Fovea:** save into the folder the export landed in.
- **Book only attached to the conversation, with no folder:** save to
  `Documents/Books/<Title>/` in OneDrive through Pinakes, creating the folder.
- If saving fails, say so plainly, keep the local copies, and send them to Kev
  as files instead.

After saving, confirm each saved file is the same size as the local copy (the
Pinakes result reports bytes). Never put the error log or the spoiler ledger
inside the review itself.

## Step 10. Deliver

- Put the finished review in the reply, ready to paste.
- After it, add a short summary line with the rating, the number of definite
  errors found (and how many were excluded as likely conversion artifacts),
  the review's word count, and whose verdict the rating reflects.
- List what the reflection and fact-check steps changed, in a sentence or two.
- If the verdict is yours rather than Kev's, include the voice caveat from the
  reflection step.
- Name the folder where both files were saved.
