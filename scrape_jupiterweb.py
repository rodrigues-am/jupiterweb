#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Webscraping das disciplinas da Licenciatura em Física no Jupiterweb.

Entrada:  transfer/coc/estrutura-curricular.csv
Saídas:   transfer/coc-db/ementas-lic.json
          transfer/coc-db/estrutura-curricular.json

Disciplinas cujo sgldis termina em XXX não existem no Jupiterweb e usam
apenas os dados da planilha CSV.

Ajustes desta versão:
- melhora a decodificação das páginas do Jupiterweb, evitando caracteres como  e ;
- limpa espaços invisíveis, &nbsp;, quebras de linha, barras invertidas e sequências literais
  como \n, \r e \t nos campos finais do JSON;
- converte aspas duplas internas para aspas tipográficas, evitando sequências \" no JSON;
- inclui cabeçalhos de avaliação como delimitadores de seção, evitando que o
  conteúdo programático capture trechos de avaliação.
"""
import csv
import html
import json
import re
import time
import urllib.error
import urllib.request
from pathlib import Path
import unicodedata

BASE_DIR = Path('/root/.hermes/hermes-agent/transfer')
CSV_PATH = BASE_DIR / 'coc' / 'estrutura-curricular.csv'
OUT_DIR = BASE_DIR / 'coc-db'
OUT_DIR.mkdir(parents=True, exist_ok=True)

USER_AGENT = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36'
TIMEOUT = 40
RETRIES = 3

SECOES_EMENTA = [
    'Ementa',
    'Objetivos',
    'Conteúdo Programático',
    'Programa',
    'Método de Ensino',
    'Critério de Avaliação',
    'Norma de Recuperação',
    'Bibliografia Básica',
    'Bibliografia Complementar',
    'Bibliografia',
    'Objetivos de Desenvolvimento Sustentável (ONU)',
    'Docente(s) Responsável(eis)',
]

# Cabeçalhos que delimitam uma seção textual na página do Jupiterweb.
# A lista inclui campos de ementa, blocos de avaliação e marcadores de rodapé.
# Eles não são todos exportados para o JSON; alguns são usados apenas para
# impedir que uma seção capture o texto da seção seguinte.
TITULOS_SECAO = SECOES_EMENTA + [
    'Instrumentos e Critérios de Avaliação',
    'Método de Avaliação',
    'Créditos Aula', 'Créditos Trabalho', 'Carga Horária Total',
    'Carga Horária de Extensão', 'Tipo', 'Ativação', 'Desativação',
    'Clique', 'Créditos', 'Fale conosco',
]

# Caracteres de controle que costumam aparecer quando aspas tipográficas em
# Windows-1252 são decodificadas como ISO-8859-1. Mantemos o mapeamento como
# proteção adicional, mesmo usando cp1252 na decodificação.
CONTROLES_CP1252 = str.maketrans({
    '\x80': '€',
    '\x82': '‚',
    '\x83': 'ƒ',
    '\x84': '„',
    '\x85': '…',
    '\x86': '†',
    '\x87': '‡',
    '\x88': 'ˆ',
    '\x89': '‰',
    '\x8a': 'Š',
    '\x8b': '‹',
    '\x8c': 'Œ',
    '\x8e': 'Ž',
    '\x91': '‘',
    '\x92': '’',
    '\x93': '“',
    '\x94': '”',
    '\x95': '•',
    '\x96': '–',
    '\x97': '—',
    '\x98': '˜',
    '\x99': '™',
    '\x9a': 'š',
    '\x9b': '›',
    '\x9c': 'œ',
    '\x9e': 'ž',
    '\x9f': 'Ÿ',
})

ESPACOS_INVISIVEIS = str.maketrans({
    '\u00a0': ' ',   # espaço não separável
    '\u1680': ' ',
    '\u180e': '',
    '\u2000': ' ',
    '\u2001': ' ',
    '\u2002': ' ',
    '\u2003': ' ',
    '\u2004': ' ',
    '\u2005': ' ',
    '\u2006': ' ',
    '\u2007': ' ',
    '\u2008': ' ',
    '\u2009': ' ',
    '\u200a': ' ',
    '\u200b': '',    # zero-width space
    '\u200c': '',
    '\u200d': '',
    '\u202f': ' ',
    '\u205f': ' ',
    '\u2060': '',
    '\u3000': ' ',
    '\ufeff': '',
    '\u00ad': '',    # soft hyphen
})


def decodificar_pagina(data):
    """Decodifica bytes do Jupiterweb com tolerância a cp1252/iso-8859-1."""
    for encoding in ('cp1252', 'iso-8859-1', 'utf-8'):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode('iso-8859-1', errors='replace')


def fetch_page(sgldis, codcur=None, codhab=None):
    """Recupera a página da disciplina no Jupiterweb."""
    params = [('sgldis', sgldis)]
    if codcur is not None:
        params.append(('codcur', codcur))
    if codhab is not None:
        params.append(('codhab', codhab))
    query = '&'.join(f'{k}={v}' for k, v in params)
    url = f'https://uspdigital.usp.br/jupiterweb/obterDisciplina?{query}'
    req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            data = r.read()
    except urllib.error.HTTPError as e:
        return url, decodificar_pagina(e.read()), True
    return url, decodificar_pagina(data), False


def normalizar_unicode(texto):
    """Remove caracteres invisíveis e corrige controles comuns de cp1252."""
    if texto is None:
        return None
    texto = texto.translate(CONTROLES_CP1252)
    texto = texto.translate(ESPACOS_INVISIVEIS)
    texto = unicodedata.normalize('NFC', texto)
    return texto


def converter_aspas_duplas(texto):
    """Converte pares de aspas duplas internas em aspas tipográficas.

    Isso evita que o JSON precise salvar trechos bibliográficos como \"Título\".
    A substituição é conservadora: só troca pares de aspas na mesma linha.
    """
    if not texto:
        return texto
    anterior = None
    while anterior != texto:
        anterior = texto
        texto = re.sub(r'"([^"\n\r]+)"', r'“\1”', texto)
    return texto


def limpar_texto_campo(texto, preservar_quebras=False):
    """Limpa um valor textual antes de exportá-lo para JSON.

    Por padrão, devolve texto em uma única linha, sem quebras de linha reais,
    sem sequências literais como \n e sem barras invertidas soltas.
    """
    if texto is None:
        return None

    texto = str(texto)
    texto = html.unescape(html.unescape(texto))
    texto = normalizar_unicode(texto)

    # Remove sequências literais vindas de textos já escapados.
    texto = re.sub(r'\\[rnt]+', ' ', texto)

    # Remove barras invertidas remanescentes que não têm utilidade no texto final.
    texto = texto.replace('\\', ' ')

    texto = converter_aspas_duplas(texto)
    texto = texto.replace('\r\n', '\n').replace('\r', '\n')
    texto = texto.replace('\t', ' ')

    if preservar_quebras:
        texto = re.sub(r'[ \f\v]+', ' ', texto)
        texto = re.sub(r' *\n *', '\n', texto)
        texto = re.sub(r'\n{3,}', '\n\n', texto)
    else:
        texto = re.sub(r'\s+', ' ', texto)

    texto = texto.strip(' \n\t;:')
    return texto or None


def clean_text(html_text):
    """Converte HTML em texto plano, preservando quebras úteis para parsing."""
    text = re.sub(r'<script\b[^>]*>.*?</script>', ' ', html_text, flags=re.IGNORECASE | re.DOTALL)
    text = re.sub(r'<style\b[^>]*>.*?</style>', ' ', text, flags=re.IGNORECASE | re.DOTALL)

    # Quebras estruturais importantes para reconhecer cabeçalhos isolados.
    text = re.sub(r'<br\s*/?>', '\n', text, flags=re.IGNORECASE)
    text = re.sub(r'</(?:p|div|tr|table|h[1-6])\s*>', '\n', text, flags=re.IGNORECASE)
    text = re.sub(r'<li\b[^>]*>', '\n- ', text, flags=re.IGNORECASE)
    text = re.sub(r'</li\s*>', '\n', text, flags=re.IGNORECASE)
    text = re.sub(r'</(?:td|th)\s*>', ' ', text, flags=re.IGNORECASE)

    text = re.sub(r'<[^>]+>', ' ', text)
    text = html.unescape(html.unescape(text))
    text = normalizar_unicode(text)

    # Normaliza espaços sem destruir as quebras usadas pelos cabeçalhos.
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    text = text.replace('\t', ' ')
    text = re.sub(r'[ \f\v]+', ' ', text)
    text = re.sub(r' *\n *', '\n', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def parse_disciplina(html_text):
    """Extrai os campos principais da página de uma disciplina."""
    text = clean_text(html_text)

    # Verifica se a página contém os dados da disciplina.
    if 'Créditos Aula' not in text or 'Disciplina:' not in text:
        return None

    # --- Identificação ---
    unidade_grupo = None
    m_unid = re.search(r'Pró-Reitoria de Graduação\s+(.*?)\s+Disciplina:', text, re.DOTALL)
    if m_unid:
        unidade_grupo = m_unid.group(1).strip()

    # Sigla e nome: "Disciplina: SIGLA - NOME". O Jupiterweb costuma
    # trazer a tradução/descrição em inglês na linha seguinte, antes dos
    # créditos; preservamos os dois campos quando disponíveis.
    m_ident = re.search(r'Disciplina:\s*([^\n-]+?)\s*-\s*(.+?)(?:\n\s*Créditos Aula:)', text, re.DOTALL)
    if not m_ident:
        return None
    sgldis = limpar_texto_campo(m_ident.group(1))
    nomes = [limpar_texto_campo(ln) for ln in m_ident.group(2).split('\n')]
    nomes = [ln for ln in nomes if ln]
    nome_disciplina = nomes[0] if nomes else None
    nome_disciplina_ingles = nomes[1] if len(nomes) > 1 else None

    # Normaliza unidade.
    unidade, grupo = None, None
    if unidade_grupo:
        partes = [limpar_texto_campo(p) for p in unidade_grupo.split('\n')]
        partes = [p for p in partes if p]
        unidade = partes[0] if partes else None
        grupo = partes[1] if len(partes) > 1 else None
    unidade = normalizar_unidade(unidade) if unidade else None

    # --- Valores numéricos ---
    cred_aula = extrair_numero(text, r'Créditos\s+Aula:\s*(\d+)')
    cred_trabalho = extrair_numero(text, r'Créditos\s+Trabalho:\s*(\d+)')
    carga_horaria_total = extrair_numero(text, r'Carga\s+Horária\s+Total:\s*(\d+)')

    if cred_aula is None or cred_trabalho is None or carga_horaria_total is None:
        return None

    # --- Extras de carga horária ---
    m_extra = re.search(r'Carga\s+Horária\s+Total:\s*\d+\s*h\s*(.*?)\s*Tipo:', text, re.DOTALL)
    extra = limpar_texto_campo(m_extra.group(1)) if m_extra else ''

    ch_pcc = extrair_numero(extra or '', r'Práticas\s+como\s+Componentes\s+Curriculares:\s*(\d+)')
    ch_estagio = extrair_numero(extra or '', r'Estágio:\s*(\d+)')
    ch_ext = extrair_numero(text, r'Carga\s+Horária\s+de\s+Extensão:\s*(\d+)')

    # --- Metadados e seções posteriores da ementa ---
    secoes = extrai_secoes(text)

    # Algumas páginas antigas/externas usam apenas "Programa" para a lista de
    # tópicos. Mantém o campo canônico esperado pelo JSON.
    if not secoes.get('conteudo_programatico'):
        secoes['conteudo_programatico'] = secoes.get('programa')

    docentes_texto = secoes.get('docente_s_responsavel_eis')

    return limpar_registro({
        'sgldis': sgldis,
        'nome_disciplina': nome_disciplina,
        'nome_disciplina_ingles': nome_disciplina_ingles,
        'unidade': unidade,
        'grupo': grupo,
        'cred_aula': cred_aula,
        'cred_trabalho': cred_trabalho,
        'carga_horaria_total': carga_horaria_total,
        'ch_pcc': ch_pcc,
        'ch_estagio': ch_estagio,
        'ch_ext': ch_ext,
        'extra': extra,
        'tipo': extrair_valor_label(text, 'Tipo'),
        'ativacao': extrair_valor_label(text, 'Ativação'),
        'desativacao': extrair_valor_label(text, 'Desativação'),
        'ementa': secoes.get('ementa'),
        'objetivos': secoes.get('objetivos'),
        'conteudo_programatico': secoes.get('conteudo_programatico'),
        'programa': secoes.get('programa'),
        'metodo_ensino': secoes.get('metodo_de_ensino'),
        'criterio_avaliacao': secoes.get('criterio_de_avaliacao'),
        'norma_recuperacao': secoes.get('norma_de_recuperacao'),
        'bibliografia': secoes.get('bibliografia'),
        'bibliografia_basica': secoes.get('bibliografia_basica'),
        'bibliografia_complementar': secoes.get('bibliografia_complementar'),
        'objetivos_desenvolvimento_sustentavel_onu': secoes.get('objetivos_de_desenvolvimento_sustentavel_onu'),
        'docentes_responsaveis': docentes_texto,
        'docentes_responsaveis_lista': extrai_docentes(docentes_texto),
    })


def normalizar_unidade(unidade):
    """Converte nome completo da unidade na sigla usada no CSV."""
    if not unidade:
        return None
    u = unidade.strip()
    # Ordenar dos mais específicos para os mais genéricos.
    if 'Fonoaudiologia' in u or 'Fisioterapia' in u or 'Terapia Ocupacional' in u:
        return 'MFT'
    if 'Filosofia, Letras e Ciências Humanas' in u or 'FFLCH' in u:
        return 'FFLCH'
    if 'Instituto de Física' in u:
        return 'IF'
    if 'Instituto de Matemática' in u:
        return 'IME'
    if 'Faculdade de Educação' in u:
        return 'FE'
    if 'Instituto de Química' in u:
        return 'IQ'
    if 'Instituto de Geociências' in u:
        return 'IGc'
    if 'Instituto de Biociências' in u:
        return 'IB'
    if 'Instituto de Astronomia' in u:
        return 'IAG'
    if 'Escola de Artes' in u:
        return 'EACH'
    if 'Medicina' in u:
        return 'MFT'
    return u


def normalizar_chave(titulo):
    """Normaliza títulos acentuados para chaves ASCII estáveis no JSON."""
    sem_acentos = ''.join(
        c for c in unicodedata.normalize('NFD', titulo.lower())
        if unicodedata.category(c) != 'Mn'
    )
    return re.sub(r'[^a-z0-9]+', '_', sem_acentos).strip('_')


def extrair_numero(texto, regex):
    m = re.search(regex, texto or '', re.IGNORECASE)
    return int(m.group(1)) if m else None


def heading_pattern(titulo):
    """Regex para cabeçalho isolado em linha, com dois-pontos opcionais."""
    return re.compile(rf'(?:^|\n)\s*{re.escape(titulo)}\s*:?\s*(?:\n|$)', re.IGNORECASE)


def limpa_secao(secao):
    """Limpa uma seção textual extraída da página."""
    if not secao:
        return None
    secao = secao.strip()
    secao = re.sub(r'\nTradução:.*', '', secao, flags=re.DOTALL)
    secao = re.sub(r'^\s*[\*:=-]+\s*', '', secao)
    secao = re.sub(r'\n{3,}', '\n\n', secao)
    return limpar_texto_campo(secao, preservar_quebras=False)


def extrai_secao(text, titulo):
    """Extrai o conteúdo entre um cabeçalho de seção e o próximo cabeçalho.

    O Jupiterweb repete palavras como "conteúdo programático" dentro dos textos
    de objetivos e também possui itens de menu com "Programa". Por isso a busca
    deve aceitar apenas títulos isolados em uma linha, nunca uma ocorrência no
    meio de um parágrafo.
    """
    m = heading_pattern(titulo).search(text)
    if not m:
        return None
    start = m.end()
    end = len(text)
    for outro in TITULOS_SECAO:
        if outro.lower() == titulo.lower():
            continue
        nm = heading_pattern(outro).search(text[start:])
        if nm:
            end = min(end, start + nm.start())
    return limpa_secao(text[start:end])


def extrai_secoes(text):
    """Extrai todas as seções textuais conhecidas da ementa Jupiterweb."""
    return {normalizar_chave(titulo): extrai_secao(text, titulo) for titulo in SECOES_EMENTA}


def extrair_valor_label(text, label):
    """Extrai valores curtos após labels como Tipo, Ativação e Desativação.

    Usa apenas espaços horizontais após a quebra de linha; `\\s*` aqui faria um
    campo vazio, como Desativação, capturar o próximo cabeçalho, como Ementa.
    """
    m = re.search(rf'(?:^|\n)\s*{re.escape(label)}\s*:\s*\n+[ \t\xa0]*([^\n]*)', text, re.IGNORECASE)
    if not m:
        m = re.search(rf'{re.escape(label)}\s*:\s*([^\n]+)', text, re.IGNORECASE)
    if not m:
        return None
    valor = limpar_texto_campo(m.group(1))
    if not valor or any(valor.lower() == t.lower() for t in TITULOS_SECAO):
        return None
    return valor


def extrai_docentes(texto):
    """Converte ocorrências '12345 - Nome' em uma lista estruturada."""
    if not texto:
        return []
    texto = limpar_texto_campo(texto) or ''
    docentes = []
    padrao = re.compile(r'(\d{3,})\s*-\s*(.*?)(?=\s+\d{3,}\s*-|$)')
    for m in padrao.finditer(texto):
        codigo = m.group(1).strip()
        nome = limpar_texto_campo(m.group(2))
        if codigo and nome:
            docentes.append({'codigo': codigo, 'nome': nome})
    return docentes


def limpar_registro(valor):
    """Aplica a limpeza final de texto recursivamente em dicts/listas."""
    if isinstance(valor, dict):
        return {k: limpar_registro(v) for k, v in valor.items()}
    if isinstance(valor, list):
        return [limpar_registro(v) for v in valor]
    if isinstance(valor, str):
        return limpar_texto_campo(valor)
    return valor


def load_csv(path):
    registros = []
    with open(path, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            registros.append(row)
    return registros


def to_int(value):
    if value is None:
        return None
    value = str(value).strip()
    if value == '':
        return None
    try:
        return int(float(value))
    except ValueError:
        return None


def build_estrutura(csv_row, web_data):
    """Monta o registro de estrutura-curricular.json."""
    sgldis = csv_row['sgldis'].strip()
    nome = (web_data.get('nome_disciplina') if web_data else None) or csv_row.get('nome_disciplina', '').strip()
    unidade = (web_data.get('unidade') if web_data else None) or csv_row.get('unidade', '').strip()
    bloco = csv_row.get('bloco', '').strip()

    if web_data:
        cht = web_data.get('carga_horaria_total')
        cred_aula = web_data.get('cred_aula')
        cred_trabalho = web_data.get('cred_trabalho')
        ch_pcc = web_data.get('ch_pcc')
        ch_ext = web_data.get('ch_ext')
    else:
        cht = to_int(csv_row.get('carga_horaria_total'))
        cred_aula = to_int(csv_row.get('cred_aula'))
        cred_trabalho = to_int(csv_row.get('cred_trabalho'))
        ch_pcc = to_int(csv_row.get('ch_pcc'))
        ch_ext = to_int(csv_row.get('ch_ext'))

    ch_aula = cred_aula * 15 if cred_aula is not None else to_int(csv_row.get('ch_aula'))
    ch_trabalho = cred_trabalho * 30 if cred_trabalho is not None else to_int(csv_row.get('ch_trabalho'))

    # Prioriza o valor do Jupiterweb para ch_estagio quando disponível.
    ch_estagio_web = web_data.get('ch_estagio') if web_data else None
    ch_estagio = ch_estagio_web if ch_estagio_web is not None else to_int(csv_row.get('ch_estagio'))

    ch_atpa = to_int(csv_row.get('ch_atpa'))

    sem_integral = to_int(csv_row.get('sem_diurno'))
    sem_noturno = to_int(csv_row.get('sem_noturno'))

    return limpar_registro({
        'sgldis': sgldis,
        'nome_disciplina': nome,
        'unidade': unidade,
        'bloco': bloco,
        'carga_horaria_total': cht,
        'ch_aula': ch_aula,
        'ch_trabalho': ch_trabalho,
        'ch_atpa': ch_atpa,
        'ch_estagio': ch_estagio,
        'ch_ext': ch_ext,
        'cred_aula': cred_aula,
        'ch_pcc': ch_pcc,
        'cred_trabalho': cred_trabalho,
        'sem_integral': sem_integral,
        'sem_noturno': sem_noturno,
    })


def build_ementa_fallback(csv_row, observacao):
    """Registro parcial para ementas-lic.json quando não há página parseável."""
    return limpar_registro({
        'sgldis': csv_row['sgldis'].strip(),
        'nome_disciplina': csv_row.get('nome_disciplina', '').strip(),
        'nome_disciplina_ingles': None,
        'unidade': csv_row.get('unidade', '').strip(),
        'grupo': None,
        'cred_aula': to_int(csv_row.get('cred_aula')),
        'cred_trabalho': to_int(csv_row.get('cred_trabalho')),
        'carga_horaria_total': to_int(csv_row.get('carga_horaria_total')),
        'ch_pcc': to_int(csv_row.get('ch_pcc')),
        'ch_estagio': to_int(csv_row.get('ch_estagio')),
        'ch_ext': to_int(csv_row.get('ch_ext')),
        'extra': '',
        'tipo': None,
        'ativacao': None,
        'desativacao': None,
        'ementa': None,
        'objetivos': None,
        'conteudo_programatico': None,
        'programa': None,
        'metodo_ensino': None,
        'criterio_avaliacao': None,
        'norma_recuperacao': None,
        'bibliografia': None,
        'bibliografia_basica': None,
        'bibliografia_complementar': None,
        'objetivos_desenvolvimento_sustentavel_onu': None,
        'docentes_responsaveis': None,
        'docentes_responsaveis_lista': [],
        'observacao': observacao,
    })


def main():
    csv_rows = load_csv(CSV_PATH)
    ementas = []
    estrutura = []
    falhas = []

    # Evita duplicatas de sgldis no scraping; o CSV pode ter linhas repetidas.
    vistos = set()

    for row in csv_rows:
        sgldis = row['sgldis'].strip()
        if sgldis in vistos:
            continue
        vistos.add(sgldis)

        if re.match(r'^.*XXX$', sgldis):
            print(f'[{sgldis}] Ignorada (código provisório).')
            estrutura.append(build_estrutura(row, None))
            ementas.append(build_ementa_fallback(
                row,
                'Disciplina ainda não cadastrada no Jupiterweb.'
            ))
            continue

        web_data = None
        erro = None
        for codhab in [0, 4]:
            for tentativa in range(1, RETRIES + 1):
                try:
                    _, html_text, _ = fetch_page(sgldis, codcur='43031', codhab=codhab)
                    parsed = parse_disciplina(html_text)
                    if parsed:
                        web_data = parsed
                        break
                    else:
                        # Se não encontrou padrão, pode ser página vazia/erro.
                        erro = 'padrão de disciplina não encontrado'
                except Exception as exc:
                    erro = str(exc)
                    time.sleep(1)
            if web_data:
                break

        if web_data is None:
            print(f'[{sgldis}] FALHA: {erro}')
            falhas.append({'sgldis': sgldis, 'erro': erro})
            # Fallback parcial: salva estrutura e ementa com dados do CSV.
            estrutura.append(build_estrutura(row, None))
            ementas.append(build_ementa_fallback(
                row,
                f'Disciplina não encontrada/parseável no Jupiterweb para codcur=43031 (codhab=0 ou 4): {erro}'
            ))
            continue

        # Validação básica.
        ch_calculada = web_data['cred_aula'] * 15 + web_data['cred_trabalho'] * 30
        if web_data['carga_horaria_total'] != ch_calculada:
            print(f"[{sgldis}] Aviso: carga horária total {web_data['carga_horaria_total']} "
                  f"diferente de {ch_calculada}")

        ementas.append(limpar_registro(web_data))
        estrutura.append(build_estrutura(row, web_data))
        print(f"[{sgldis}] OK - {web_data['nome_disciplina']} ({web_data['unidade']}) "
              f"CA={web_data['cred_aula']} CT={web_data['cred_trabalho']} CHT={web_data['carga_horaria_total']}")
        time.sleep(0.5)

    # Dedup estrutura por sgldis, escolhendo a entrada mais completa.
    estrutura_dedup = {}
    for reg in estrutura:
        sgldis = reg['sgldis']
        completo = lambda r: sum(1 for v in r.values() if v is not None and v != '')
        if sgldis not in estrutura_dedup or completo(reg) > completo(estrutura_dedup[sgldis]):
            estrutura_dedup[sgldis] = reg
    estrutura = list(estrutura_dedup.values())

    # Limpeza final de segurança antes de salvar os JSONs.
    ementas = limpar_registro(ementas)
    estrutura = limpar_registro(estrutura)

    # Salva JSONs.
    with open(OUT_DIR / 'ementas-lic.json', 'w', encoding='utf-8') as f:
        json.dump(ementas, f, ensure_ascii=False, indent=2)
        f.write('\n')

    with open(OUT_DIR / 'estrutura-curricular.json', 'w', encoding='utf-8') as f:
        json.dump(estrutura, f, ensure_ascii=False, indent=2)
        f.write('\n')

    print(f'\nTotal processado: {len(csv_rows)} linhas')
    print(f'Disciplinas distintas: {len(vistos)}')
    print(f'Ementas salvas: {len(ementas)}')
    print(f'Falhas: {len(falhas)}')
    if falhas:
        print('Falhas:', falhas)


if __name__ == '__main__':
    main()
