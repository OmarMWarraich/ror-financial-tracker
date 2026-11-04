# Project knowledge

Before responding to each user request or taking action, silently assess whether
the context already available is sufficient for that request. Reuse relevant
conversation, session memory, and prior tool results; do not repeat retrieval or
other tool calls merely as a ritual. Simple conversational replies need no
repository lookup.

Before substantial implementation, debugging, architecture, or provider work,
identify any missing, uncertain, or potentially stale task-relevant facts.
Retrieve only those gaps with `ruby bin/project-knowledge "<topic>"`; skip the
command when relevant records and their sources are already available and still
applicable. Start with "ALVIS Equibles", "Kraken connection modes", or
"Hotwire Native" for those integrations. Use a focused query rather than loading
the entire plan. Repeat a query only when the topic, evidence, or underlying
store has changed, or earlier results were insufficient.

In a new or resumed session, do not assume memory has parity with the repository.
Check the available context for the task's decisions, implementation status,
sources, and freshness. A remembered claim without identifiable evidence or
known applicability is not verified context. If these cannot be established,
retrieve the relevant records once and consult only the cited code or sources
needed to resolve remaining uncertainty. Parity is task-specific, not proof that
all repository knowledge has been loaded; dates alone do not prove freshness.
If memory conflicts with current evidence, reconcile the discrepancy before
relying on it: current code establishes implementation, and explicit new user
decisions can supersede recorded plans. Do not silently treat either as the other.

The curated store is [config/project_knowledge.json](../config/project_knowledge.json).
Results distinguish verified facts, user decisions, open questions, and
implemented behavior; preserve those distinctions. Follow the cited sources
when freshness or an implementation detail matters. No match is not proof that
a feature is unsupported.

Before declaring relevant work complete, update affected records for changed
requirements, verified provider facts, implemented behavior, and resolved open
questions. Preserve stable IDs; replace outdated claims rather than appending
contradictory duplicates. Include sources and the actual update date. Add a new
record only for reusable project knowledge, not every edit or test run.
Validate store changes with `bundle exec ruby test/lib/project_knowledge_test.rb`
and check a representative query against the changed fact.

For every authorized commit, review the staged changes against the knowledge
store before committing. Include affected fact/decision/status/source updates
in that same commit, not a later cleanup. Do not mark planned work implemented
until verified. If no reusable knowledge changes, leave records and their dates
unchanged and state that the retrieval review required no updates. Do not create
commits merely to satisfy this rule; commit only when authorized.

Keep secrets, private account information, and raw chats out of the store.
Read the current direction in [plan.md](../plan.md), not its superseded appendix,
when that local file exists. [todo.md](../todo.md) and the plan are Git-ignored:
never force-add or unignore them to share context. Keep reusable non-sensitive
decisions and implementation facts in the shared knowledge store instead.

Local Copilot agents with terminal access can run the retrieval command. In
environments without terminal access, consult the JSON store directly. GitHub
agents can access only files available in their checkout; sharing requires the
instructions, store, CLI, and library to be committed and pushed when authorized.
Instructions guide use; do not claim automatic ingestion, enforced hooks,
universal inline-completion retrieval, or guaranteed model-token savings.
