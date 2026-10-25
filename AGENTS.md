# AGENTS.md — npass-tui

## Objetivo

Este repositório contém uma interface de terminal (TUI) em Bash para o `npass`. A TUI é uma camada de navegação e interação; **o executável `npass` continua sendo a autoridade para criptografia, parsing, armazenamento e operações sobre segredos**.

## Mapa do projeto

| Tarefa | Arquivo inicial |
|---|---|
| Interface, teclado, telas e fluxo principal | `npass-tui` |
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
8. Não interprete a saída decorativa de comandos como `npass identities` como API estruturada estável. Para listagem de caminhos, prefira `npass ls --flat ID` na versão atual do npass-store; confira `docs/CLI-AUDIT.md` e valide o contrato antes de depender de outra versão.
9. Não suponha que extensões opcionais estejam instaladas ou habilitadas. Detecte indisponibilidade e mostre uma mensagem clara.
10. A TUI não deve afirmar que uma operação é segura só porque a interface a escondeu. Limpe previews e códigos secretos da tela quando sair deles ou após ações sensíveis, sempre que viável.

## Fluxo de desenvolvimento

1. Leia este arquivo e a seção correspondente de `IMPLEMENTATION-ROADMAP.md`.
2. Inspecione apenas o trecho de `npass-tui` e os testes relacionados à mudança.
3. Adicione/atualize testes com um executável `npass` simulado; não use o cofre real em testes automatizados.
4. Valide sintaxe com `bash -n npass-tui` e execute os testes disponíveis no repositório/CI.
5. Atualize `README.md` e o roadmap quando atalhos ou comportamentos mudarem.
6. Não declare testes interativos aprovados se só foi validada a sintaxe. Testes com PTY/mock não substituem validação manual em terminal real.

## Segurança e UX

- Ações de remover, sobrescrever, mover entre identidades ou alterar OTP/PIN devem mostrar identidade e caminho completos e explicar efeitos colaterais relevantes antes de confirmar.
- Ao editar ou executar comandos interativos, preserve stdin/stdout/stderr conectados ao terminal.
- Não despeje resultados de busca de conteúdo ou documentos secretos em mensagens de status.
- Mantenha navegação por setas e atalhos documentados consistentes; atalhos desconhecidos não devem disparar ações.
- Prefira alterações pequenas, testáveis e reversíveis. Não replique na TUI regras de negócio que já pertencem ao `npass`.
