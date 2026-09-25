# Q-omics 연구 참고 스냅샷 (2026-09-24)

암 다중오믹스 분석 플랫폼 **Q-omics** 를 이 저장소에서 연구 참고용으로 볼 때의 요약입니다.
아래 수치는 2026-09-24 에 Q-omics MCP 서버에 직접 질의해 받은 것이며, 플랫폼이 갱신되면
달라집니다. **환자·참여자 데이터는 들어 있지 않습니다** — 공개 코호트의 표본 수만 적었습니다.

> 짝 자료: `https://claude.ai/share/1a644a8b-f0d4-4eda-8d72-7f90b4b25ca1` (대표님이 공유한 대화).
> 이 문서를 만든 작업 환경에서는 그 페이지의 본문을 읽을 수 없어 **그 대화의 분석 결과는
> 아직 옮기지 못했습니다.** 본문을 받으면 §6 에 붙입니다.

---

## 1. 무엇인가

- TCGA(조직) · CPTAC(질량분석 단백질·인산화) · CCLE / NCI60(세포주) · CRISPR / shRNA 스크린을
  한데 모아 **미리 계산해 둔 통계 결과**(p 값, 군 크기, 배수변화, 상관, 합의 점수)를 돌려줍니다.
- 모든 답은 데이터에서 나오고, 생성된 문장이 아닙니다. 결과가 비어 있으면 「저장된 유의 결과가
  없다」는 뜻이지 「측정을 안 했다」는 뜻이 아닙니다(기본 테이블만 전수).
- 이름은 서버가 풀어 줍니다: 유전자·약물·GO 용어는 그대로, 암종은 이름이나 코드(`LUAD`, `luad`,
  `lung adenocarcinoma`)로. **영어만** 통합니다. 모호하면(「melanoma」→ UVM / SKCM) 추측하지 않고
  되묻습니다.

## 2. 데이터 층 (Data_Type)

| 층 | 뜻 | 비고 |
|---|---|---|
| rna / rna_normal | mRNA 발현 (종양 / 정상) | |
| mutation | 체세포 돌연변이 유무 | `info_mutation` 약 338만 행 |
| protein_ms / _normal | 질량분석 단백질량 (CPTAC) | |
| protein_rppa | RPPA 단백질량 | |
| immune_cell / _normal | 침윤세포 농축 점수 64종 | 분율이 아님 — 합이 1 이 안 됨. 면역세포 외에 기질·상피형도 포함 |
| methylation · met_probe · met_rep | DNA 메틸화 (셋으로 나뉨) | 순위를 낼 때는 유전자 수준 `met_rep` 만 |
| drug | 세포주 약물 감수성 (−log IC50) | CCLE |
| sgrna / shrna | CRISPR / shRNA 의존성 (부호 뒤집어 저장) | |
| go_* | GO 유전자군 점수 (rna · protein_ms · methylation · sgrna · shrna) | |
| neo_* | 신항원 입력 (돌연변이형 / 야생형) | CPTAC 만 |

## 3. 코호트 (표본 수, 2026-09-24 질의)

### 조직 — TCGA (34 암종, 총 10,023)

```
BRCA 1068 · UCEC 538 · KIRC 523 · LGG 506 · THCA 501 · HNSC 498 · PRAD 493 · LUAD 490
LUSC 488 · SKCM 453 · COAD 430 · BLCA 401 · OV 372 · LIHC 365 · STAD 346 · CESC 291
KIRP 283 · SARC 256 · PCPG 178 · PAAD 176 · ESCA 160 · READ 157 · GBM 150 · TGCT 134
LAML 130 · THYM 117 · MESO 84 · ACC 79 · UVM 78 · SCLC 77 · KICH 64 · UCS 54 · DLBC 47 · CHOL 36
```

### 조직 — CPTAC (10 암종, 총 1,518 · 질량분석)

```
UCEC 240 · LUAD 229 · CCRCC 220 · PDAC 170 · BRCA 134 · HNSC 110 · LSCC 108 · COAD 105 · OV 103 · GBM 99
```

### 조직 — PEMB (Pembrolizumab 임상 반응 코호트, 총 124)

```
Metastatic_Urothelial_Carcinoma 46 · Melanoma 28 · Ovarian_Cancer 26 · Triple_Negative_Breast_Cancer 16 · Thymic_Carcinoma 8
```

### 세포주 — CCLE (20 계통, 총 1,288)

```
BLOOD_Leukemia 123 · CNS 102 · BLOOD_Lymphoma 100 · SKIN 88 · LUNG_NSCLC_LUAD 85 · LARGE_INTESTINE 72
LUNG_SCLC 71 · SOFT_TISSUE 71 · BONE 68 · OVARY 67 · UPPER_AERODIGESTIVE_TRACT 66 · BREAST 62
PANCREAS 55 · KIDNEY 51 · STOMACH 45 · URINARY_TRACT 38 · OESOPHAGUS 38 · BLOOD_Myeloma 30
LUNG_NSCLC_LUSC 29 · LIVER 27
```

### 세포주 — NCI60 (약물 유도 발현 변화, 60주)

세포주 계통은 `lineage_map`(24 행)으로 TCGA 조직 계통과 이어집니다 (예: BREAST ↔ BRCA).

## 4. 분석 종류 (MCP 도구 이름 기준)

| 도구 | 묻는 것 | 표본 | 비고 |
|---|---|---|---|
| `survival` | 어떤 지표로 나눈 두 군의 생존 차이 (KM, logrank) | 조직 | OS/DFS, 1·3·5년, 병기·성별 제한 가능 |
| `nt` | 정상 vs 종양 한 지표 차이 | 조직 | |
| `box` | 군별 분포 · 범암종 프로파일 | 조직·세포 | |
| `correlation` | 두 지표 산점도 + 상관계수 | 조직·세포 | |
| `cross` | 한 지표 vs 한 데이터 층 전체 (volcano) | 조직·세포 | 효과값은 군 분할 배수변화이지 Pearson r 이 아님. CCLE 약물 경로 |
| `response` | RECIST 반응군 vs 비반응군을 가르는 지표 | 조직 | **다중검정 보정 없음** — 아래 §5 |
| `browse` | 합의 점수로 매긴 상위 목록 (생존·N/T·연관·합성치사) | 조직·세포 | 「상위 몇 개」 질문의 표 답 |
| `consensus` · `pair_consensus` | 한 결과의 견고성 재확인 | 조직 | S_Cscore · L_Cscore |
| `sl` | 합성치사 파트너 (BRCA × PARP 형) | 조직·세포 | |
| `dig` | 약물이 바꾸는 유전자 발현 (NCI60, 4 용량) | 세포 | 약물 15 종만 |
| `neoantigen` | 돌연변이 단백질 신항원 후보 | CPTAC | 계통 구분 없음 |
| `pql_*` | 개수·빈도·필터·교차표 (자유 질의) | | `pql_examples` → `pql_run` |

## 5. 읽을 때 조심할 것

- **S_Cscore ≠ L_Cscore.** S 는 한 암종 안 216 가지 표본추출 조건 중 유의한 수(재현성), L 은
  34 개 TCGA 암종 중 유의한 수(범암종성). 둘 다 한 방향만 셉니다.
- **저장된 행 = 유의한 행이 아닌 표가 있습니다.** `q_nt` · `q_survival_*` · `q_sl_*` 는 p<0.05 만
  저장(없음 = 유의하지 않음)하지만, `q_cross_asso` · `q_cross_response` · `q_DIG` · `q_neoantigen` 은
  p 가 1.0 인 행까지 저장합니다. PQL 로 직접 읽으면 도구가 주는 것보다 2~4 배 많은 행이 나오므로
  **어느 층을 인용했는지** 적어야 합니다.
- **`response` 는 보정이 없습니다.** 약 22,000 개 지표를 t 검정하므로 p=0.001 이 우연으로 22 번쯤
  나옵니다. 플랫폼 자체 측정(2026-09-16)으로 28 명 Melanoma 코호트는 p<0.05 유전자가 우연 기대치보다
  **적고**(811 vs 1,117), FDR 을 넘는 것이 없습니다. 순위는 출발점이지 결론이 아닙니다. 코호트 크기를
  같이 적으세요.
- PEMB 코호트는 S_Cscore 축이 없어 0 으로 나옵니다 — 「재현 안 됨」이 아니라 「측정 안 함」입니다.
- 방향 접두사 `X_Y_*` / `Y_X_*` 는 **누가 나눴는지**를 뜻합니다 (X 로 나눠 Y 를 잼 / 그 반대).
  효과값과 p 는 같은 방향에서 가져와야 합니다.

## 6. 이 연구실에 닿는 지점

메디노트는 복약관리 앱이고 Q-omics 는 종양학 자료라 화면에 직접 들어갈 것은 없습니다.
다만 아래는 겹칩니다.

- **임상 약물 반응 기록의 약물 목록** (`info_sample_drug_response`, TCGA 2,388 건 + PEMB 124 건 · 상위 31 종):
  Cisplatin 361 · 5-Fluorouracil 231 · Paclitaxel 188 · Carboplatin 183 · Gemcitabine 180 ·
  Cyclophosphamide 157 · Doxorubicin 129 · Temozolomide 127 · Pembrolizumab 124 · Docetaxel 108 ·
  Leucovorin 105 · Etoposide 80 · Oxaliplatin 76 · Capecitabine 62 · Bleomycin 51 · Pemetrexed 48 ·
  Epirubicin 42 · Vinorelbine 35 · Dacarbazine 27 · Bevacizumab 27 · Leuprolide 21 · Bicalutamide 18 ·
  Sorafenib 17 · Irinotecan 16 · Cetuximab 16 · Tamoxifen 16 · Lomustine 15 · Ipilimumab 14 ·
  Trastuzumab 14 · Ifosfamide 13 · Anastrozole 11
- **NCI60 약물 유도 발현 약물 15 종**: Vorinostat · Bortezomib · Doxorubicin · Geldanamycin ·
  Topotecan · Sorafenib · Gemcitabine · Dasatinib · 5-azacytidine · Lapatinib · Sirolimus · Cisplatin ·
  Erlotinib · Sunitinib · Paclitaxel
- 위 약물명은 영어 INN 이라, 메디노트의 약물 사전과 맞출 때는 성분명 기준으로 이어야 합니다.

### 공유 대화의 분석 결과 — 대기

`https://claude.ai/share/1a644a8b-f0d4-4eda-8d72-7f90b4b25ca1` 의 본문(질문 · 분석 · 표)을 받으면
여기에 붙입니다. 그 대화에서 나온 유전자·약물·암종 이름과 p 값·군 크기를 그대로 옮기고,
§5 의 주의(보정 없음 · 코호트 크기)를 함께 답니다.

## 7. 다시 만드는 법

이 문서의 수치는 Q-omics MCP 서버에 다음을 물어 얻었습니다.

```
pql_schema
pql_run  Q('info_sample').group_by(['Dataset','Sample_Type','Lineage_Name']).agg(n=count())
pql_run  Q('info_sample_drug_response').group_by(['Dataset','Drug_name']).agg(n=count())
pql_run  Q('q_DIG').group_by(['Drug_Name']).agg(n=count())
```
