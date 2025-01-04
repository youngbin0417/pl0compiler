
%{
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "s_interpreter.c"
FILE *fp;
void yyerror(char*);
int yylex();

#define CONST 	0
#define VAR 	1
#define PROC 	2
#define IDENT 	3  /* CONST + VAR */

#define TBSIZE 100	// symbol table size
#define LVLmax 20		// max. level depth
#define HASHSIZE 7
#define MAX_OFFSET 100

struct {	// symbol table
	char name[20];	/*변수 이름*/
	int type;		/* 0-CONST	1-VARIABLE	2-PROCEDURE */
	int lvl;	/*변수의 level*/
	int offst;	/*offset 값*/
	int dimension;	/*0-var	1-array*/
	int length;		/*배열 길이*/
	int link;		/*backward chain에 쓸 link*/
	} table[TBSIZE];



int hashBucket[HASHSIZE]; // 해시 버켓
int leveltable[LVLmax]; // 레벨 테이블
int arrayBaseOffset = MAX_OFFSET;
	
int block[LVLmax]; 	// Data for Set/Reset symbol table
typedef struct { // address format
	int l;
	int a;
	} Addr;

int Lookup(char *, int);  // lookup sym name for type, 
		      // if found setup LDiff/OFFSET and return 1 else return 0
void Enter(char *, int, int, int, int, int); // symbol insert
void SetBlock();
void ResetBlock();
void DisplayTable(); // symbol table dump
int GenLab(char *);	// label 생성(번호와 label) 및 현재 코드주소 저장
void EmitLab(int);	// label 출력 및 forward jump 주소 확정
void EmitLab1(int);	// label 출력 및 backward jump 주소 저장
void EmitPname(char *label);	// procedure 이름 출력
void Emit1(char *, fct, int, int);  // INT, LOD, LIT, STO 코드생성
void Emit2(char *, int, char *);  // CAL 코드생성
void Emit3(char *, fct, int);	// jmp, jpc 코드 생성
void Emit(char *, int);	// opr 코드생성
void EmitOut(char *, fct); // Out 코드 생성
int HashFunction(char *);
void InitializeSymbolTable();

int ln=1, cp=0;
int lev=0;
int tx=0; // stack smbol table top pt.
int level=0; // block nesting level
int cdx=0; // code addr
int LDiff=0, OFFSET=0; // nesting level diff, offset(상대주소)
int Lno=0;
int avail=0; // 해시 구조에서 현재 사용할 테이블 index
char Lname[10]; // 생성된 label
int Lab[20]; // 새로 생성된 label 에 대한 코드주소 저장(테이블)
%}

%union {
	char ident[50];	// id lvalue
	int number;	// num lvalue
	}
%token TCONST TVAR TPROC TCALL TBEGIN TIF TTHEN TWHILE TDO TEND ODD NE LE GE ASSIGN TWRITE
%token <ident> ID 
%token <number> NUM
%token '[' ']'
%type <number> Dcl VarDcl Ident_list ProcHead
%left '+' '-'
%left '*' '/'
%left UM

%%
Program: Block '.' 
	{  Emit("END", 7); printf("\n ==== valid syntax ====\n"); } ;
Block: { Emit3("JMP", Jmp, $<number>$=GenLab(Lname) ); } 
	Dcl { EmitLab($<number>1); Emit1("INT", Int, 0, $2); } 
	Statement { DisplayTable(); } ;
Dcl: ConstDcl VarDcl ProcDef_list 	{ $$=$2; } ;
ConstDcl:
	| TCONST Constdef_list ';' ;
Constdef_list: Constdef_list ',' ID '=' NUM 	{ Enter($3, CONST, level, $5, 0, 0);	 }
	| ID '=' NUM 	{ Enter($1, CONST, level, $3, 0, 0); }  ;
VarDcl: TVAR Ident_list ';'	{ $$=$2;	 }
	|		{ $$=3; }  ;
Ident_list: Ident_list ',' ID '[' NUM ']' {	Enter($3, VAR, level, arrayBaseOffset, 1, $5); $$ = $1 + 1;	}
	| Ident_list ',' ID	{ Enter($3, VAR, level, $1, 0, 0); $$=$1+1; }
	| ID '[' NUM ']' {	Enter($1, VAR, level, arrayBaseOffset, 1, $3); $$=1;	} // 여기 $$값 주는 것 바꾸면 배열이 따로 인덱스를 빼지 않아도 될것 같음.
	| ID 		{ Enter($1, VAR, level, 3, 0, 0); $$=4; }  ;
ProcDef_list: ProcDef_list ProcDef
	| 	 ;
ProcDef: ProcHead	{ SetBlock(); } Block ';' { Emit("RET", 0); ResetBlock(); }  ;
ProcHead: TPROC ID ';' { Enter($2, PROC, level, cdx, 0, 0); EmitPname($2); }  ;
Statement: ID '[' Expression ']' {
    if (Lookup($1, VAR)) {
        // 인덱스 Expression(`i`)이 이미 평가되어 스택에 푸시됨
        // 배열의 기본 주소를 로드하고, 인덱스를 더함
        Emit1("LDA", Lda, LDiff, OFFSET); // base address 푸시 (100)
        Emit("ADD", 2); // base + i 계산, 스택에 푸시
    }
} ASSIGN Expression {
    if (Lookup($1, VAR)) {
        // 할당할 값 Expression(`expr`)이 이미 평가되어 스택에 푸시됨
        Emit1("STI", Sti, 0, 0);           // `expr` 값을 `base + i` 주소에 저장
    }
}
	| ID ASSIGN Expression { Lookup($1, VAR); Emit1("STO", Sto, LDiff, OFFSET); }
	| TCALL ID		{ 	Lookup($2, PROC); Emit2("CAL", LDiff, $2);		 }
	| TBEGIN Statement_list TEND
	| TIF Condition 		{ 	Emit3("JPC", Jpc, $<number>$=GenLab(Lname));	 }
		TTHEN Statement	{ 	EmitLab($<number>3);	 }
	| TWHILE 		{ EmitLab1($<number>$=GenLab(Lname) ); }
        Condition { Emit3("JPC", Jpc, $<number>$=GenLab(Lname)); }
		TDO Statement 	{ Emit3("JMP", Jmp, $<number>2); EmitLab($<number>4); }
	| TWRITE ID '[' Expression ']' {
    	if (Lookup($2, VAR)) {
        	Emit1("LDA", Lda, LDiff, OFFSET);
			Emit("ADD", 2);
        	Emit1("LDI", Ldi, 0, 0);
        	EmitOut("OUT", Out);
	    } else {
        	printf("Error: '%s' is not declared as an array.\n", $2);
    	}
}
	| TWRITE ID		{ Lookup($2,VAR); Emit1("LOD", Lod, LDiff, OFFSET); EmitOut("OUT",Out); }
	| error	 {  yyerrok; }
	|
	;
Statement_list: Statement_list ';' Statement
	| Statement  
	;
Condition: ODD Expression		{ 	Emit("ODD",6);	 }
	| Expression '=' Expression	{  Emit("EQL",8);	}
	| Expression NE Expression	{  Emit("NE", 9);    }
	| Expression '<' Expression	{ 	Emit("LSS",10);	 }
	| Expression '>' Expression	{ 	Emit("GTR",12);	}
	| Expression GE Expression	{ 	Emit("GEQ", 11);	}
	| Expression LE Expression	{ 	Emit("LEQ", 13);	}  ;
Expression: Expression '+' Term	{ Emit("ADD", 2) }
	| Expression '-' Term	{ Emit("SUB", 3);  }
	| '+' Term %prec UM
	| '-' Term %prec UM	{ 	Emit("NEG", 1);	 }
	| Term ;
Term: Term '*' Factor		{ 	Emit("MUL", 4);	 }
	| Term '/' Factor		{ Emit("DIV", 5);	 }
	| Factor ;
Factor: ID '[' Expression ']' { 
		if (Lookup($1, VAR)) {
	    	Emit1("LDA", Lda, LDiff, OFFSET);  
        	Emit("ADD", 2); 
        	Emit1("LDI", Ldi, 0, 0);
    	} else {
        	printf("Error: '%s' is not declared as an array.\n", $1);
	 	}
	} 
	| ID	{ /* ID lookup 결과로 LOD 또는 LIT 코드 생성 */
			  if (Lookup($1, VAR)) Emit1("LOD", Lod, LDiff, OFFSET);
			  else  Emit1("LIT", Lit, 0, OFFSET);
			 }
	| NUM		{ Emit1("LIT", Lit, 0, $1); }
	| '(' Expression ')' ;
	
%%
#include "lex.yy.c"
void yyerror(char* s) {
	printf("line: %d cp: %d %s\n", ln, cp, s);
}
int Lookup(char *name, int type) {
	// 심볼 검색후 찾으면 LDiff(level diff)와 OFFSET(상대주소)를 지정하고 1을 리턴
	// 없으면 0을 리턴
    int hashIndex = HashFunction(name);  // 해시 값 계산
    int idx = hashBucket[hashIndex];    // 해당 해시 버킷의 첫 번째 심볼 인덱스
    LDiff = -1; OFFSET = -1;

    // Backward Chain을 따라 검색
    while (idx != -1) {
        if (strcmp(table[idx].name, name) == 0) {  // 이름 일치
            LDiff = level - table[idx].lvl;       // 레벨 차이 계산
            OFFSET = table[idx].offst;           // 오프셋 설정
            if (table[idx].type == type) {       // 타입 일치 여부 확인
                return 1;  // 심볼 찾음
            } else {
                return 0;  // 이름은 같지만 타입 불일치
            }
        }
        idx = table[idx].link;  // 다음 노드로 이동
    }

    return 0;  // 심볼을 찾지 못함
}

void InitializeSymbolTable() {
    for (int i = 0; i < HASHSIZE; i++) {
        hashBucket[i] = -1;  // -1로 초기화하여 비어 있음을 나타냄
    }
	for (int i = 0; i < LVLmax; i++) {
        leveltable[i] = -1;  // 각 레벨의 시작 인덱스 초기화
    }
}


int HashFunction(char *name){
	unsigned int hash = 0;
	while (*name) {
        hash = (hash * 31) + *name;  // 31은 적당한 소수로, 충돌을 줄이는 데 유용
        name++;
    }
    return hash % HASHSIZE;
}

void Enter(char *name, int type, int lvl, int offst, int dimension, int length) {
    int hashIndex = HashFunction(name); // 해시 버켓 인덱스
    int idx = hashBucket[hashIndex];   // 해시 버켓에 담겨있는 심볼 테이블 인덱스

	if (leveltable[level] == -1) {
        leveltable[level] = avail;  // 현재 레벨의 첫 심볼 인덱스 기록
    }

    // 중복 심볼 검사
    while (idx != -1) {
        if (strcmp(table[idx].name, name) == 0 && table[idx].lvl == lvl) {
            printf("Error: Duplicate symbol '%s' at level %d\n", name, lvl);
            return;  // 중복 심볼 발견 시 추가하지 않고 종료
        }
        idx = table[idx].link;  // 다음 연결된 노드
    }

    // 심볼 테이블에 심볼 정보 저장
    strcpy(table[avail].name, name);
    table[avail].type = type;
    table[avail].lvl = lvl;
    table[avail].dimension = dimension;
    table[avail].length = (dimension == 1) ? length : 0;
    table[avail].offst = offst;

    // 배열일 경우, `arrayBaseOffset` 업데이트
    if (dimension == 1) {
        arrayBaseOffset += length;  // 배열 크기만큼 오프셋 증가
    }

    // Backward Chain 설정
    table[avail].link = hashBucket[hashIndex];  // 이전 심볼과 연결
    hashBucket[hashIndex] = avail;             // 현재 심볼을 버킷의 맨 앞에 추가

    ++avail;  // 다음 사용 가능한 인덱스로 이동
}


void SetBlock() {
	block[level++]=avail;
	}

void ResetBlock() { 
	int idx=block[--level];
	if(idx !=-1){
		for(int i = idx; i <avail;i++){
			int hashIndex = HashFunction(table[i].name);
			if(hashBucket[hashIndex]==i){
				hashBucket[hashIndex]=table[i].link;
			}
		}
		avail=idx;
		leveltable[level]=-1;
	}
	}

void DisplayTable() {
	int idx=avail;
	printf("\n======== sym tbl contents ==========\n");
	
    while (--idx>=0) { // 역순으로 출력
        printf("%s  %d  %d  %d	", 
               table[idx].name, 
               table[idx].type, 
               table[idx].lvl,
			   table[idx].link);

        if (table[idx].dimension == 0) {
            printf("OFFSET: %d\n", table[idx].offst);
        } else {
            printf("ARRAY ADDRESS: %d | LENGTH: %d\n", 
                	table[idx].offst, 
                   table[idx].length);
        }
    }
    printf("---------------------------------------------------\n");
}



int GenLab(char *label) {
	Lab[Lno]=cdx;	// save code addr. for backward jump
	sprintf(label, "LAB%d", Lno);
	return Lno++;
}
void EmitLab(int label) {	// resolve forward jump label
	Code[Lab[label]].a=cdx; // fixed up forward jump label
	printf("LAB%d\n", label);
}
void EmitLab1(int label) {
	Lab[label]=cdx; /* GenLab() 에서 시행 */
	printf("LAB%d\n", label);
}
void EmitPname(char *label) {
	printf("%s\n", label);
}
void Emit1(char *code, fct op, int ld, int offst) {   // INT, LOD, LIT, STO 코드생성, ld: level_diff.
	Instruction i;
	printf("%d	%s	%d	%d\n", cdx, code, ld, offst);
	i.f=op; i.l=ld; i.a=offst;
	Code[cdx++]=i;
}
void Emit2(char *code, int ld, char *name) {	// CAL 코드생성, ld: level_diff., OFFSET:code_addr.
	Instruction i;
	printf("%d	%s	%d	%s\n", cdx, code, ld, name);
	i.f=Cal; i.l=ld; i.a=OFFSET; // ld: level_diff.
	Code[cdx++]=i;
}
void Emit3(char *code, fct op, int label) {  // jmp, jpc 코드생성
	Instruction i;
	printf("%d	%s	LAB%d\n", cdx, code, label);
	i.f=op; i.l=0; i.a=Lab[label]; 	// fixed up backward jump
	Code[cdx++]=i;
}
void Emit(char *code, int op) {	// Opr 코드생성
	Instruction i;
	printf("%d	%s\n", cdx, code);
	i.f=Opr; i.l=0; i.a=op;
	Code[cdx++]=i;
}
void EmitOut(char *code, fct op) {
    Instruction i;
    printf("%d\t%s\n", cdx, code); 
    i.f = op; i.l = 0; i.a = 0;
	Code[cdx++] = i;
}

void main() {
	InitializeSymbolTable();
	if (yyparse()) return;
	printf("===== Binary Code =====\n");
	fp=fopen("pl0.code", "w");
	for (int i=0; i<=cdx; i++) {
		printf("%d	%d	%d	%d\n", i, Code[i]);
		fprintf(fp, "%d	%d	%d	%d\n", i, Code[i]);
}
	fclose(fp);
	printf("------------------------------\n");
	interprete();
}
