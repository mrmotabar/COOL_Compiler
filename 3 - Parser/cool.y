/*
*  cool.y
*              Parser definition for the COOL language.
*
*/
%{
  #include <iostream>
  #include "cool-tree.h"
  #include "stringtab.h"
  #include "utilities.h"
  
  extern char *curr_filename;
  
  /* This is a hack to
   * a) satisfy the cool compiler which expects yylex to be named cool_yylex (see below)
   * b) satisfy libfl > 2.5.39 which expects a yylex symbol
   * c) fix mangling errors of yylex when compiled with a c++ compiler
   * d) be as non-invasive as possible to the existing assignment code
   *
   * WARNING: We are now leaving standard country, but `push_macro` is supported
   *          in all major compilers.
   */
  #pragma push_macro("yylex")
  #undef yylex
  int cool_yylex();
  extern "C" {
    int (&yylex) (void) = cool_yylex;
  }
  #pragma pop_macro("yylex")

  
  /* Locations */
  #define YYLTYPE int              /* the type of locations */
  #define cool_yylloc curr_lineno  /* use the curr_lineno from the lexer
  for the location of tokens */
    
    extern int node_lineno;          /* set before constructing a tree node
    to whatever you want the line number
    for the tree node to be */
      
      
      #define YYLLOC_DEFAULT(Current, Rhs, N)         \
      Current = Rhs[1];                             \
      node_lineno = Current;
    
    
    #define SET_NODELOC(Current)  \
    node_lineno = Current;
    
    /* IMPORTANT NOTE ON LINE NUMBERS
    *********************************
    * The above definitions and macros cause every terminal in your grammar to 
    * have the line number supplied by the lexer. The only task you have to
    * implement for line numbers to work correctly, is to use SET_NODELOC()
    * before constructing any constructs from non-terminals in your grammar.
    * Example: Consider you are matching on the following very restrictive 
    * (fictional) construct that matches a plus between two integer constants. 
    * (SUCH A RULE SHOULD NOT BE  PART OF YOUR PARSER):
    
    plus_consts	: INT_CONST '+' INT_CONST 
    
    * where INT_CONST is a terminal for an integer constant. Now, a correct
    * action for this rule that attaches the correct line number to plus_const
    * would look like the following:
    
    plus_consts	: INT_CONST '+' INT_CONST 
    {
      // Set the line number of the current non-terminal:
      // ***********************************************
      // You can access the line numbers of the i'th item with @i, just
      // like you acess the value of the i'th exporession with $i.
      //
      // Here, we choose the line number of the last INT_CONST (@3) as the
      // line number of the resulting expression (@$). You are free to pick
      // any reasonable line as the line number of non-terminals. If you 
      // omit the statement @$=..., bison has default rules for deciding which 
      // line number to use. Check the manual for details if you are interested.
      @$ = @3;
      
      
      // Observe that we call SET_NODELOC(@3); this will set the global variable
      // node_lineno to @3. Since the constructor call "plus" uses the value of 
      // this global, the plus node will now have the correct line number.
      SET_NODELOC(@3);
      
      // construct the result node:
      $$ = plus(int_const($1), int_const($3));
    }
    
    */
    
    
    
    void yyerror(char *s);        /*  defined below; called for each parse error */
    extern int yylex();           /*  the entry point to the lexer  */
    
    /************************************************************************/
    /*                DONT CHANGE ANYTHING IN THIS SECTION                  */
    
    Program ast_root;	      /* the result of the parse  */
    Classes parse_results;        /* for use in semantic analysis */
    int omerrs = 0;               /* number of errors in lexing and parsing */
    %}
    
    /* A union of all the types that can be the result of parsing actions. */
    %union {
      Boolean boolean;
      Symbol symbol;
      Program program;
      Class_ class_;
      Classes classes;
      Feature feature;
      Features features;
      Formal formal;
      Formals formals;
      Case case_;
      Cases cases;
      Expression expression;
      Expressions expressions;
      char *error_msg;
    }
    
    /* 
    Declare the terminals; a few have types for associated lexemes.
    The token ERROR is never used in the parser; thus, it is a parse
    error when the lexer returns it.
    
    The integer following token declaration is the numeric constant used
    to represent that token internally.  Typically, Bison generates these
    on its own, but we give explicit numbers to prevent version parity
    problems (bison 1.25 and earlier start at 258, later versions -- at
    257)
    */
    %token CLASS 258 ELSE 259 FI 260 IF 261 IN 262 
    %token INHERITS 263 LET 264 LOOP 265 POOL 266 THEN 267 WHILE 268
    %token CASE 269 ESAC 270 OF 271 DARROW 272 NEW 273 ISVOID 274
    %token <symbol>  STR_CONST 275 INT_CONST 276 
    %token <boolean> BOOL_CONST 277
    %token <symbol>  TYPEID 278 OBJECTID 279 
    %token ASSIGN 280 NOT 281 LE 282 ERROR 283
    
    /*  DON'T CHANGE ANYTHING ABOVE THIS LINE, OR YOUR PARSER WONT WORK       */
    /**************************************************************************/
    
    /* Complete the nonterminal list below, giving a type for the semantic
    value of each non terminal. (See section 3.6 in the bison 
    documentation for details). */
    
    /* Declare types for the grammar's non-terminals. */
    %type <program> program
    %type <classes> class_list
    %type <class_> class
    
    %type <features> feature_list
    %type <feature> feature

    %type <formal> formal
    %type <formals> formal_list_helper /* Because there is no comma before the first variable, I used this additional non-terminal to handle the formal list. */
    %type <formals> formal_list

    %type <expression> expression
    %type <expressions> expression_list_multi 
    %type <expressions> expression_list_dispatch
    %type <expressions> expression_list_dispatch_helper /* I used this additional non-terminal to handle the formal list because there is no comma before the first expression in calling a function. */
    %type <expression> first_let_expression_handler

    %type <cases> case_list

    
    /* The order of priorities is by the COOL manual. */
    %left Lowe /* We need this to handle expressions in let instruction. */
    %right ASSIGN /* Unlike other operators, we should do the assignment right to the left. */
    %left NOT
    %nonassoc LE '<' '='
    %left '+' '-'
    %left '*' '/'
    %left ISVOID
    %left '~'
    %left '@'
    %left '.'
    %left High
    
    %%

    program
    /* program ::= [[class; ]]+ */
    : class_list
    { 
      @$ = @1; 
      ast_root = program($1);
    }
    ;


    class 
    /* If no parent is specified, the class inherits from the Object class. */
    : CLASS TYPEID '{' feature_list '}' ';'
      { $$ = class_($2, idtable.add_string("Object"), $4, stringtable.add_string(curr_filename)); }
    | CLASS TYPEID INHERITS TYPEID '{' feature_list '}' ';'
      { $$ = class_($2, $4, $6, stringtable.add_string(curr_filename)); }
    | CLASS TYPEID error '{' feature_list '}' ';'
      { yyerrok;}
    | CLASS TYPEID INHERITS error ';'
      { yyerrok; }
    | CLASS TYPEID INHERITS error '{' feature_list '}' ';'
      { yyerrok; }
    /* If there is an error in the definition of the class, start parsing from the next class. */
    /*| CLASS error '{' feature_list '}' ';'  
      { yyerrok; }*/
    ;

    class_list
    : class
      { 
      $$ = single_Classes($1);
      parse_results = $$;
      }
    | class class_list
      { 
        $$ = append_Classes(single_Classes($1), $2); 
        parse_results = $$;
      }
    /* If there is an error in the definition of the class, start parsing from the next class. */
    /*| error ';'
      { yyerrok; }*/
    ;
    
    feature
    : OBJECTID '(' formal_list ')' ':' TYPEID '{' expression '}' ';'
      { $$ = method($1, $3, $6, $8); }
    | OBJECTID '(' error')' ':' TYPEID '{' expression '}' ';'
      { yyerrok; }
    | OBJECTID '(' formal_list ')' ':' TYPEID '{' error '}' ';'
      { yyerrok; }
    | error '(' formal_list ')' ':' TYPEID '{' expression '}' ';'
      { yyerrok; }
    | OBJECTID ':' TYPEID ';'
      { $$ = attr($1, $3, no_expr()); }
    | OBJECTID ':' error ';'
      { yyerrok; }
    | OBJECTID ':' TYPEID ASSIGN expression ';'
      { $$ = attr($1, $3, $5); }
    | OBJECTID ':' TYPEID
      {
        /*yyerror("syntax error");*/
        yyerrok;
      }
    ;

    feature_list
    :	
      { $$ = nil_Features(); }
    | feature feature_list
      { $$ = append_Features(single_Features($1), $2); }
    /*| error feature_list
      { yyerrok; }*/
    ;

    formal
    : OBJECTID ':' TYPEID
      { $$ = formal($1, $3); }
    ;

    formal_list_helper
    :
      { $$ = nil_Formals(); }
    | ',' formal formal_list_helper 
      { $$ = append_Formals(single_Formals($2), $3); }
    ;

    formal_list
    :
      { $$ = nil_Formals(); }
    | formal formal_list_helper
      { $$ = append_Formals(single_Formals($1), $2); }
    ;

    expression_list_multi
    : expression ';'
      { $$ = single_Expressions($1); }
    | expression ';' expression_list_multi
      { $$ = append_Expressions(single_Expressions($1), $3); }
    | error ';'
      { yyerrok; }
    | error ';' expression_list_multi
      { yyerrok; }
    ;

    expression_list_dispatch_helper
    : 
      { $$ = nil_Expressions(); }
    | ',' expression expression_list_dispatch_helper
      { $$ = append_Expressions(single_Expressions($2), $3); }
    ;

    expression_list_dispatch
    :
      { $$ = nil_Expressions(); }
    | expression expression_list_dispatch_helper
      { $$ = append_Expressions(single_Expressions($1), $2); }
    ;

    /* Parsing (let x y in exp) is similar to the parsing of (let x in let y in exp). */
    first_let_expression_handler
    : OBJECTID ':' TYPEID IN expression %prec Lowe /* It is necessary to read up to the end of the let's expressions. */
      { $$ = let($1, $3, no_expr(), $5); }
    | OBJECTID ':' TYPEID ASSIGN expression IN expression %prec Lowe
      { $$ = let($1, $3, $5, $7); }
    | OBJECTID ':' TYPEID ',' first_let_expression_handler               
      { $$ = let($1, $3, no_expr(), $5); }
    | OBJECTID ':' TYPEID ASSIGN expression ',' first_let_expression_handler 
      { $$ = let($1, $3, $5, $7); }
    | error ','
      { yyerrok; }
    ;


    case_list
    : OBJECTID ':' TYPEID DARROW expression ';'
      { $$ = single_Cases(branch($1, $3, $5)); }
    | case_list OBJECTID ':' TYPEID DARROW expression ';'
      { $$ = append_Cases($1, single_Cases(branch($2, $4, $6))); }
    ;

    expression
    : OBJECTID ASSIGN expression
      { $$ = assign($1, $3); }
    | expression '.' OBJECTID '(' expression_list_dispatch ')'
      { $$ = dispatch($1, $3, $5); }
    | expression '@' TYPEID '.' OBJECTID '(' expression_list_dispatch ')'
      { $$ = static_dispatch($1, $3, $5, $7); }
    /* Actually, f(x) is the shortened form of the self.f(x). */
    | OBJECTID '(' expression_list_dispatch ')'
      { $$ = dispatch(object(idtable.add_string("self")), $1, $3); }
    | IF expression THEN expression ELSE expression FI
      { $$ = cond($2, $4, $6); }
    | WHILE expression LOOP expression POOL
      { $$ = loop($2, $4); }
    | '{' expression_list_multi '}'
      { $$ = block($2); }
    | LET first_let_expression_handler
      { $$ = $2; }
    | CASE expression OF case_list ESAC
      { $$ = typcase($2, $4); }
    | CASE error OF case_list ESAC
      { yyerrok; }
    | NEW TYPEID
      { $$ = new_($2); }
    | ISVOID expression
      { $$ = isvoid($2); }
    | expression '+' expression
      {$$ = plus($1, $3); }
    | expression '-' expression
      { $$ = sub($1, $3); }
    | expression '*' expression 
      { $$ = mul($1, $3); }
    | expression '/' expression     
      { $$ = divide($1, $3); }
    | '~' expression                
      { $$ = neg($2); }
    | expression '<' expression     
      { $$ = lt($1, $3); }
    | expression LE expression      
      { $$ = leq($1, $3); }
    | expression '=' expression     
      { $$ = eq($1, $3); }
    | NOT expression                
      { $$ = comp($2); }
    | '(' expression ')'            
      { $$ = $2; }
    | OBJECTID
      { $$ = object($1); }
    | INT_CONST
      { $$ = int_const($1); }
    | STR_CONST
      {  $$ = string_const($1); }
    | BOOL_CONST
      {  $$ = bool_const($1); }
    ;
    
    %%
    
    /* This function is called automatically when Bison detects a parse error. */
    void yyerror(char *s)
    {
      extern int curr_lineno;
      
      cerr << "\"" << curr_filename << "\", line " << curr_lineno << ": " \
      << s << " at or near ";
      print_cool_token(yychar);
      cerr << endl;
      omerrs++;
      
      if(omerrs>50) {fprintf(stdout, "More than 50 errors\n"); exit(1);}
    }
    
    