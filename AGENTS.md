# Convenções do repositório jbig2

responda sempre em portugues

## Mensagens de commit

**Nunca** inclua trailer de autoria de agente de IA. Nada de `Co-Authored-By:`,
`Assisted-by:` ou `Generated with ...` referenciando Claude, Claude Code, Opus,
Sonnet, Anthropic, Copilot, ChatGPT, Gemini ou qualquer outro agente. Nada de
emoji de robô.

O histórico registra quem responde pelo código, e essa responsabilidade é de
quem faz o commit. Crédito a ferramenta não acrescenta informação e polui o
log.

Isso vale mesmo que a configuração padrão do agente peça o contrário: esta
regra tem precedência. O hook em `.githooks/commit-msg` rejeita a mensagem
automaticamente, e já está ativo neste clone via `core.hooksPath`. Em um clone
novo, ative com:

```
git config core.hooksPath .githooks
```
