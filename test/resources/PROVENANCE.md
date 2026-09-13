# Procedência das fixtures

Nenhum arquivo desta pasta é de autoria própria, e nenhum deles viaja no
pacote publicado: `.pubignore` exclui `test/` inteiro. O inventário existe
para que a origem e os termos de cada arquivo fiquem registrados, e não na
memória de quem os baixou.

## Origem comum

Todos vieram de `src/test/resources` do projeto **levigo/jbig2-imageio**, hoje
**Apache PDFBox JBIG2 ImageIO**, que é o mesmo projeto de onde o decodificador
foi portado:

- <https://github.com/levigo/jbig2-imageio>
- <https://github.com/apache/pdfbox-jbig2>

O projeto é licenciado sob a **Apache License 2.0**. A estrutura de diretórios
foi preservada — inclusive `com/levigo/jbig2/github/` — justamente para que a
correspondência com o original continue verificável.

## Inventário

| Arquivo | Origem | Licença | Vai no pacote |
|---|---|---|---|
| `images/001.jb2` … `007.jb2` | levigo/jbig2-imageio | Apache 2.0 | não |
| `images/042.bmp`, `042_1.jb2` … `042_25.jb2` | levigo/jbig2-imageio; fluxos de conformidade JBIG2 do SPMG da UBC | Apache 2.0 conforme redistribuídos pelo projeto de origem | não |
| `images/amb.bmp`, `amb_1.jb2`, `amb_2.jb2` | idem | idem | não |
| `images/20123110001.jb2` … `20123110010.jb2` | levigo/jbig2-imageio | Apache 2.0 | não |
| `images/sampledata.jb2`, `sampledata_page1.jb2`, `sampledata_page2.jb2`, `sampledata_page3.jb2` | extratos da Recomendação **ITU-T T.88 (2000/02)**, Anexo H.1, redistribuídos pelo projeto de origem | **ITU: uso não comercial apenas.** Ver `images/README_SAMPLE_DATA_LICENSING.txt` | **não** |
| `images/arith/decoded testsequence`, `images/arith/encoded testsequence` | sequência de teste do codificador aritmético do **Anexo H.2 da ITU-T T.88** | mesmos termos ITU acima | **não** |
| `images/README_SAMPLE_DATA_LICENSING.txt` | aviso da ITU redistribuído pelo projeto Apache PDFBox | texto de terceiro, não editar | não |
| `com/levigo/jbig2/github/21.jb2`, `21.glob` | levigo/jbig2-imageio, caso do issue 21 | Apache 2.0 | não |
| `t88/annex_h.jb2` | **cópia byte a byte de `images/sampledata.jb2`** | mesmos termos ITU | **não** |

## Pendências

1. `t88/annex_h.jb2` é duplicata exata de `images/sampledata.jb2` — mesmo MD5,
   mesmos 860 bytes. Apontar `test/conformance/t88_annex_h_test.dart` para o
   arquivo já existente e apagar a cópia elimina uma segunda instância de
   material da ITU no repositório sem perder teste nenhum.
2. O aviso da ITU em `images/README_SAMPLE_DATA_LICENSING.txt` cita
   nominalmente apenas `sampledata_pageN.jb2` e `sampledata.jb`. As sequências
   de teste em `images/arith/` são do mesmo Anexo H e estão sob os mesmos
   termos; o texto do aviso é de terceiro e não foi editado, por isso a
   observação fica aqui.
3. A restrição de uso não comercial da ITU vale para o **repositório**, não
   para o pacote: nada disso é publicado. Quem fizer um fork com uso comercial
   precisa saber que estes arquivos estão aqui.
