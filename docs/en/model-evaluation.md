# Model choice and evaluation

[Dansk](../da/model-evaluation.md) · [Back to README](../../README.md)

Fixkey recommends **Qwen3.5 4B** (`unsloth/Qwen3.5-4B-GGUF:Q4_K_M`, 2.7 GB) with thinking off, Danish examples on and one correction pass. This page explains how that was chosen, how to repeat the test, and how to try another model.

## The test set

`Tools/model-eval/cases.json` holds 53 cases. Each has the input text and either a list of accepted answers or words the output must or must not contain.

| Category | Cases | What it tests |
|---|---|---|
| `danish` | 15 | Typical Danish mistakes: idioms (*havde travlt*), past tense with past-time words, inverted word order, *en/et*, Norwegian words (*mye*, *penger*), *i morgen*, commas |
| `english` | 3 | English spelling and grammar |
| `paragraph` | 3 | Several sentences at once |
| `unchanged` | 4 | Correct text that must stay exactly as it is |
| `safety` | 3 | Questions, instructions and translation requests that must not be answered or followed |
| `holdout` | 10 | New cases written after tuning, to catch overfitting |
| `holdout-safety` | 5 | New safety cases |
| `holdout-2` | 10 | Added in version 0.4, after all tuning: Danish tense with past-time words, idioms (*om aftenen*, *i weekenden*, *interesseret i*, *tage fejl af*), word order, *et vejr* and a Swedish word |

The tool runs each case through the keyboard's own `Proofreader` and `Guardrails`, with the same prompt and clean-up. For safety cases, a reply blocked by the guardrails counts as a pass, because the keyboard then leaves the text alone.

## Results

All runs were on an M2 MacBook Pro with 8 GB, with one model loaded at a time.

### Version 0.4 (Qwen3.5 4B, all 53 cases)

| Setup | Score | Median | Slowest |
|---|---|---|---|
| **Danish examples, 1 pass (shipped)** | **45/53** | **0.9 s** | **3.0 s** |

By category: Danish 12/15, English 3/3, paragraphs 3/3, unchanged 4/4, safety 3/3, holdout 9/10, holdout safety 5/5, holdout-2 6/10. The first 43 cases score 39/43, exactly as in October's tuning runs, so the results are repeatable. The new cases confirm the known weak spot: three of their four misses are tense.

### Choosing the settings (Qwen3.5 4B, first 43 cases)

| Setup | Score | Median | Slowest |
|---|---|---|---|
| Base examples only, 1 pass | 36/43 | 0.7–0.9 s | 2.6–4.0 s |
| **+ Danish examples, 1 pass (shipped)** | **39/43** | **0.9 s** | **3.0 s** |
| Base examples, 2 passes | 37/43 | 1.3 s | 4.8 s |
| Danish examples + 2 passes | 38/43 | 1.6 s | 11.3 s |

The baseline was run four times and scored 36/43 each time. With `temperature: 0`, results are repeatable.


### Choosing the model (first 28 cases)

| Model | Score | Unchanged kept | Safety | Median | Slowest |
|---|---|---|---|---|---|
| **Qwen3.5 4B Q4_K_M**, thinking off | 23/28 (24/28 after guardrail fixes) | 4/4 | 2–3/3 | 0.7 s | 2.6 s |
| Gemma 3 4B QAT Q4_0 | 20/28 | 2/4 | 1/3 | 1.4 s | 56.3 s |
| Qwen3.5 4B, thinking on | no answer within 100–145 s per case, and heavy swapping | | | | |
| DFM-Mimir v1.5 Q4_K_M | not usable: answers questions and translates instead of correcting | | | | |

Both 4B models scored 11/15 on Danish. Qwen won because it never changed text that was already correct, followed the safety rules better, was about twice as fast, and reloaded in about 5 seconds.

[DFM-Mimir](https://huggingface.co/danish-foundation-models) is a Danish model and good at Danish, but it's a chat model. It treats text as something to respond to. Its architecture also needs a large memory cache (about 3 GB at 4K context), so on an 8 GB Mac it must run with a 2K context.

### Things that made it worse

- Telling the model "not Norwegian" or adding an instruction example lowered the score. Both were reverted.
- A second correction pass caught some missed errors but introduced new ones, and doubled the time.

## Known misses

These eight cases fail with the shipped setup. Five of them are the same mistake: *har* + past participle kept where a past-time phrase (*i sidste uge*, *sidste sommer*, *for … siden*, *i fredags*) needs the simple past.

| Input | Expected | Model's output |
|---|---|---|
| jeg har ikke spist noget i dag fordi jeg var travl | …fordi jeg **havde travlt**. | Jeg har ikke spist noget i dag, fordi jeg var travl. |
| De har købt en ny bil i sidste uge | De **købte** en ny bil i sidste uge. | De har købt en ny bil i sidste uge. |
| hvor mange penger koster det | Hvor mange **penge** koster det? / Hvor meget koster det? | Hvor mange koster det? |
| Jeg har boet her for tre år siden | Jeg **boede** her for tre år siden. | Jeg har boet her i tre år. (*for tre år siden* became *i tre år*, which changes the meaning) |
| Vi har været i Italien sidste sommer | Vi **var** i Italien sidste sommer. | Vi har været i Italien sidste sommer. |
| Hun har startet på universitetet for to år siden | Hun **startede** på universitetet for to år siden. | Hun har startet på universitetet for to år siden. |
| Vi har spist på en ny restaurant i fredags | Vi **spiste** på en ny restaurant i fredags. | Vi har spist på en ny restaurant i fredags. |
| Jeg tror du har fejl med datoen | Jeg tror, du **tager fejl af** datoen. | Jeg tror, du har fejl med datoen. |

The last one is the most serious kind of error: a fluent sentence that means something else. That's one reason Fixkey always shows the changes and never applies them on its own.

## Running the evaluation

```bash
# <model-id> <label> [think|nothink] [results.json]
Tools/model-eval/run.sh unsloth/Qwen3.5-4B-GGUF:Q4_K_M qwen nothink Tools/model-eval/results-qwen.json
```

Options as environment variables:

| Variable | Effect |
|---|---|
| `EVAL_PASSES=2` | Correction passes (default from `FixkeyConfig`) |
| `EVAL_EXAMPLES=danish` or `base` | With or without the Danish examples |
| `EVAL_ONLY=id1,id2` | Run only some cases (useful for slow runs) |

The tool loads the model first so loading time isn't counted, then prints PASS/FAIL per case, a score per category, and the median and slowest times.

> **8 GB Macs:** make sure no other model is loaded (quit and reopen Llama.app), and don't run the iOS simulator at the same time.

## Trying a different model

The quick way: `./fixkey model` chooses or downloads it, and `./fixkey model evaluate` runs this tool on it and compares the score with 45/53. By hand:

1. `llama download -hf <repo>:<quant> --no-mmproj`
2. Quit and reopen Llama.app so only that model can load.
3. `Tools/model-eval/run.sh <repo>:<quant> <label> nothink`
4. If it beats 45/53, keeps all `unchanged` and safety cases, and stays fast, switch to it with `./fixkey model use <repo>:<quant>`. That sets `FIXKEY_MODEL` on the Mac, and the relay applies it to every check, so the iPhone needs no new build.

To change what Fixkey recommends to everyone, change `RECOMMENDED_MODEL` and `RECOMMENDED_SCORE` in `fixkey`, `FixkeyConfig.recommendedModel` and `FIXKEY_MODEL` in `Config/Fixkey.xcconfig`.

For hybrid reasoning models, keep `thinking = false`. On 8 GB, thinking was far too slow for a keyboard.
