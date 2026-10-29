# AGENTS.md — npass-tui

## Objetivo

Este repositório contém uma interface de terminal (TUI) em Bash para o `npass`. A TUI é uma camada de navegação e interação; **o executável `npass` continua sendo a autoridade para criptografia, parsing, armazenamento e operações sobre segredos**.

## Mapa do projeto

| Tarefa | Arquivo inicial |
|---|---|
| Interface, teclado, telas e fluxo principal | `lib/*.bash` (entrada e loop em `lib/99-main.bash`) |
| Montagem e instalação | `build.sh` (gera `bin/npass-tui`), `install.sh` |
| Auditoria dos contratos da CLI e decisões de integração | `docs/CLI-AUDIT.md` |
| Plano de funcionalidades pendentes | `IMPLEMENTATION-ROADMAP.md` |
| Testes de fluxos TUI | `tests/entry-create.bats`, `tests/entry-edit.bats`, `tests/entry-delete.bats` |
| Driver PTY determinístico | `tests/pty_driver.py` |
| Helpers de teste | `tests/test_helper.bash` |
| CI e validação automática | `.github/workflows/ci.yml` |
| Documentação de uso | `README.md` |

## Regras arquiteturais

1. **Use a CLI pública do `npass`.** Não leia nem altere diretamente o store, o mapa cifrado, blobs, arquivos GPG ou funções internas da implementação.
2. Não implemente um parser alternativo para o formato de entrada (atualmente documentado pelo `npass-store` como md1). Para preview, use `npass show --raw ID CAMINHO`; para campos, prefira `npass get` quando compatível com a versão instalada.
3. Não passe senhas, segredos OTP ou documentos secretos em argumentos de processo, variáveis de ambiente, logs ou arquivos temporários próprios da TUI. Deixe a CLI solicitar segredos de forma interativa.
4. Nunca adicione `-f`/ `--force` implicitamente. Preserve as confirmações nativas; operações destrutivas precisam de confirmação explícita na TUI.
5. Trate toda saída do cofre como entrada não confiável. Remova sequências ANSI/OSC e caracteres de controle antes de desenhar texto na tela. Não altere o caminho original passado à CLI apenas para sanitizar sua representação visual.
6. Verifique o código de saída de cada chamada. Saída vazia não significa sucesso.
7. Antes de chamar `npass insert`, `npass edit` ou outro comando interativo, restaure o estado original do terminal e mostre o cursor. Após o retorno, restaure o modo da TUI mesmo em caso de erro; não deixe o terminal preso em modo raw.
8. Não interprete a saída decorativa de comandos como `npass identities` como API estruturada estável. **Versão-alvo de compatibilidade: npass-store 2.8.** Para listar caminhos, use `npass ls --flat ID`. Não implemente fallback para `npass tree` nem compatibilidade com 2.5 sem uma nova decisão explícita do projeto.
9. Não suponha que extensões opcionais estejam instaladas ou habilitadas. Detecte indisponibilidade e mostre uma mensagem clara.
10. A TUI não deve afirmar que uma operação é segura só porque a interface a escondeu. Limpe previews e códigos secretos da tela quando sair deles ou após ações sensíveis, sempre que viável.

## Requisito obrigatório para toda IA/agente: testes comportamentais

**Esta regra se aplica a qualquer IA, agente automatizado ou pessoa que implemente, altere ou corrija código neste repositório. Não é uma sugestão nem pode ser ignorada por conveniência, falta de tempo ou por a alteração parecer pequena.** Toda função, comportamento ou funcionalidade nova ou modificada DEVE incluir testes comportamentais que verifiquem a TUI e confirmem que ela respeita o fluxo planejado, não apenas testes unitários isolados ou uma verificação de sintaxe Bash. Os testes devem ser criados ou atualizados junto com a implementação, no mesmo conjunto de mudanças. Se não for possível executar os testes, o agente deve informar isso explicitamente e não declarar a tarefa concluída.

- Teste o fluxo normal e o resultado visível/estado esperado da interface.
- Teste cancelamento e entradas inválidas quando aplicáveis.
- Teste falha da CLI, códigos de saída não zero e saída inesperada; confirme que a TUI não anuncia sucesso indevidamente.
- Verifique os argumentos exatos passados à CLI simulada, incluindo identidade/caminho, e confirme que flags perigosas como `-f` não são acrescentadas implicitamente.
- Para fluxos interativos, teclado, confirmações, alternância de tela ou estado do terminal, prefira testes Bats com o driver PTY determinístico.
- Para conteúdo não confiável, segredos ou operações sensíveis, teste sanitização, ausência de vazamento em argv/log/status e limpeza/restauração pertinente.
- Use mocks/fixtures isolados. **Nunca use o cofre pessoal em testes automatizados.**
- Toda regressão encontrada deve ganhar um teste que falhe antes da correção e passe depois dela, sempre que reproduzível.
- Inclua os novos testes no CI. Não marque uma tarefa concluída se a cobertura comportamental correspondente estiver faltando ou falhando.

## Fluxo de desenvolvimento

1. Leia este arquivo e a seção correspondente de `IMPLEMENTATION-ROADMAP.md`.
2. Inspecione apenas o trecho de `lib/` e os testes relacionados à mudança.
3. Antes ou junto da implementação, defina os comportamentos esperados e escreva/atualize os testes com um executável `npass` simulado.
4. Implemente a menor alteração que satisfaça os testes, sem ampliar o escopo sem necessidade.
5. Valide sintaxe com `bash build.sh && bash -n bin/npass-tui` e execute os testes relevantes; execute a suíte completa e o CI quando possível.
6. Atualize `README.md` e o roadmap quando atalhos ou comportamentos mudarem.
7. Não declare testes interativos aprovados se só foi validada a sintaxe. Testes com PTY/mock não substituem validação manual em terminal real.

## Segurança e UX

- Ações de remover, sobrescrever, mover entre identidades ou alterar OTP/PIN devem mostrar identidade e caminho completos e explicar efeitos colaterais relevantes antes de confirmar.
- Ao editar ou executar comandos interativos, preserve stdin/stdout/stderr conectados ao terminal.
- Não despeje resultados de busca de conteúdo ou documentos secretos em mensagens de status.
- Mantenha navegação por setas e atalhos documentados consistentes; atalhos desconhecidos não devem disparar ações.
- Prefira alterações pequenas, testáveis e reversíveis. Não replique na TUI regras de negócio que já pertencem ao `npass`.

## Estrutura de código

Lógica em `lib/NN-nome.bash`, concatenada em ordem por `build.sh` no arquivo único `bin/npass-tui` (gerado, no `.gitignore`; **nunca edite `bin/`**). `lib/99-main.bash` (sempre o último) faz as checagens de ambiente e roda `main_loop`. Libs não podem ter efeitos colaterais ao serem carregadas além de definir funções e variáveis, porque os testes as carregam isoladamente com `source`. Todo texto vindo da CLI deve passar por `sanitize_text`/`put`. Terminal cooked para filhos interativos: `cooked_mode`; de volta: `raw_mode`.
