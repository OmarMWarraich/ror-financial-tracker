# Project knowledge

Before architecture or provider-integration work, retrieve relevant established
facts with `ruby bin/project-knowledge "<topic>"`. Start with "ALVIS Equibles"
or "Kraken connection modes" for those integrations.

The curated store is [config/project_knowledge.json](../config/project_knowledge.json).
Results distinguish verified facts, user decisions, open questions, and
implemented behavior; preserve those distinctions. Follow the cited sources
when freshness or an implementation detail matters. No match is not proof that
a feature is unsupported.

Correct outdated records when requirements or verified sources change. Do not
append contradictory duplicates. Keep secrets, private account information,
and raw chats out of the store. Read the current direction in [plan.md](../plan.md),
not its explicitly superseded historical appendix.
