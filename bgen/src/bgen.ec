#include "debug.eh"

import "ecere"

import "debug"

import "consoleApp"
import "ecom"
import "stringTools"

import "DynamicString"
import "miscTypes"

import "econe"
import "ectwo"
import "str"
import "tmp"
import "out"
import "gen"

import "genC"
import "genCPP"
import "genCSharp"
import "genJava"
import "genPython"

const char ln = '\n';
const char * sln = "\n";

ConsoleFile console { };
//define app = (ConsoleApplication)__thisModule.application;

enum ArgSym : ArgumentSymbol
{
   quiet,
   language,
   bind,
   all,
   reset,
   string,
   map,
   tell,
   directory,
   enumPrefix,
   funcRename,
   C = 1025,
   CPlusPlus,
   CSharp,
   Java,
   Python,
   _
};

enum ArgErr : ArgumentError
{
   taskTwice,
   langTwice,
   mustSpecifyLib,
   unspecifiedLibBeforeReset,
   unspecifiedAdditionalLib,
   _
};

ApplicationData ad { };
class ApplicationData
{
   AVLTree<String> allSpecs { };

   void printAllSpecs()
   {
      AVLNode<String> node;
      PrintLn("allSpecs(", allSpecs.count, ")");
      for(node = allSpecs.root.minimum; node; node = node.next)
      {
         PrintLn(node.key);
      }
   }

   ~ApplicationData()
   {
      allSpecs.Free();
      if(allSpecs.GetCount()) conmsg("check");
      //allSpecs.RemoveAll();
   }
}

public class BGen : ConsoleApplication // <ArgSym>
{
   bool quiet;
   bool forAll;
   const char * idnt;
   int targetBits;
   idnt = " ";
   Gen gen;
   Library lib;
   Language lang;
   Directory dir;
   GenOptions options;
   GenOptions optionsForAll;
   List<Gen> gens { };
   List<Library> libs { };
   List<Library> ownLibs { };
   List<Directory> dirs { };
   List<Directory> ownDirs { };
   List<GenOptions> ownOptions { };
   String cpath;

   void onBuildArgumentOptions()
   {
      addArgumentSymbol(ArgSym::quiet,       "quiet",                super,   0);
      addArgumentSymbol(ArgSym::examples,    "examples",             super,   0);
      addArgumentSymbol(ArgSym::C,           "c",                    strict,  0);
      addArgumentSymbol(ArgSym::C,           "c89",                  strict,  0);
      //addArgumentSymbol(ArgSym::C,           "c90",                  strict,  0);
      //addArgumentSymbol(ArgSym::C,           "c95",                  strict,  0);
      //addArgumentSymbol(ArgSym::C,           "c99",                  strict,  0);
      //addArgumentSymbol(ArgSym::C,           "c11",                  strict,  0);
      addArgumentSymbol(ArgSym::CPlusPlus,   "c++",                  strict,  0);
      addArgumentSymbol(ArgSym::CPlusPlus,   "cxx",                  strict,  0);
      addArgumentSymbol(ArgSym::CPlusPlus,   "cpp",                  strict,  0);
      addArgumentSymbol(ArgSym::CPlusPlus,   "cplusplus",            strict,  0);
      addArgumentSymbol(ArgSym::CSharp,      "c#",                   strict,  0);
      addArgumentSymbol(ArgSym::CSharp,      "cs",                   strict,  0);
      addArgumentSymbol(ArgSym::CSharp,      "csharp",               strict,  0);
      addArgumentSymbol(ArgSym::Java,        "java",                 strict,  0);
      addArgumentSymbol(ArgSym::Python,      "py",                   strict,  0);
      addArgumentSymbol(ArgSym::Python,      "python",               strict,  0);
      addArgumentSymbol(ArgSym::all,         "all",                  strict,  0);
      addArgumentSymbol(ArgSym::reset,       "reset",                strict,  0);
      addArgumentSymbol(ArgSym::string,      "string",               super,   0);
      addArgumentSymbol(ArgSym::enumPrefix,  "enumeration-prefix",   super,   ArgSym::string);
      addArgumentSymbol(ArgSym::map,         "map",                  super,   0);
      addArgumentSymbol(ArgSym::funcRename,  "function-rename",      super,   ArgSym::map);
      addArgumentSymbol(ArgSym::tell,        "tell",                 super,   0);
      addArgumentSymbol(ArgSym::directory,   "output",               super,   0);
      addArgumentSymbol(ArgSym::directory,   "directory",            super,   0);

      /*
      PrintLn("------------------------------------------------------------------------------------------");
      PrintLn("------------------------------------------------------------------------------------------");
      printAllSymbolMatches(0);
      PrintLn("------------------------------------------------------------------------------------------");
      PrintLn("------------------------------------------------------------------------------------------");
      printAllSymbolMatches(ArgSym::string);
      PrintLn("------------------------------------------------------------------------------------------");
      PrintLn("------------------------------------------------------------------------------------------");
      printAllSymbolMatches(ArgSym::map);
      */

      setArgumentSpec(ArgSym::quiet,     { option, many });
      setArgumentSpec(ArgSym::examples,  { task, once, goal });
      setArgumentSpec(ArgSym::C,         { option, once, ArgSym::language });
      setArgumentSpec(ArgSym::CPlusPlus, { option, once, ArgSym::language });
      setArgumentSpec(ArgSym::CSharp,    { option, once, ArgSym::language });
      setArgumentSpec(ArgSym::Java,      { option, once, ArgSym::language });
      setArgumentSpec(ArgSym::Python,    { option, once, ArgSym::language });
      setArgumentSpec(ArgSym::string,    { option, many });
      setArgumentSpec(ArgSym::map,       { option, many });
      setArgumentSpec(ArgSym::tell,      { option, many });
      setArgumentSpec(ArgSym::directory, { option, once });
   }

   void init()
   {
      ConsoleApplication::init();

      // reserved or keywords or whatnot
      enumValueNames.Add((char*)"null");
      enumValueNames.Add((char*)"true");
      enumValueNames.Add((char*)"false");
      enumValueNames.Add((char*)"rewind");
      enumValueNames.Add((char*)"open");
      enumValueNames.Add((char*)"close");
      enumValueNames.Add((char*)"read");
      enumValueNames.Add((char*)"write");
      enumValueNames.Add((char*)"tan");
      enumValueNames.Add((char*)"round");
      enumValueNames.Add((char*)"abort");

      // CharCategory vs Pi
      enumValueNames.Add((char*)"Pi");

      // Alignment
      enumValueNames.Add((char*)"left");
      enumValueNames.Add((char*)"right");
      enumValueNames.Add((char*)"center");

      // some ec1 app init:
      targetBits = GetHostBits();
      SetTargetBits(targetBits);
      SetBGenSymbolSwapCallback(bgenSymbolSwap);
   }

   void Main()
   {
      ArgSym task = bind;
      ArgErr error = null;
      ArgErr argError = null;

      init();

      if(argc > 1)
      {
         int c;
         ArgSym sym = null;
         ArgSym prev = null;
         ArgSym nsym = null;
         ArgSym scope = null;
         for(c = 1; c < argc; c++)
         {
            ArgErr err = null;
            const char * arg = argv[c];
            const char * str = arg;
            bool nextIsValidSymbol = false;
            if(*str == '-') { str++; if(*str == '-') { str++; if(*str == '-') str++; } }
            nsym = (ArgSym)getSwitchSymbol(str, scope);
            nextIsValidSymbol = !(nsym == null || nsym == ambiguous);
            prev = sym;
            /*if(arg[0] == '.' && arg[1] == 0)
            {
               sym = null;
               PrintLn("catching . for null sym");
            }
            else */if(prev == map)
            {
               char * copy = CopyString(arg);
               char * type = copy;
               char * next = strchr(copy, ',');
               if(next) *next = 0;
               sym = (ArgSym)getSwitchSymbol(type, scope);
               if(sym == ArgSym::funcRename)
               {
                  Map<String, String> m = null;
                  options = getOptions();
                  if(options)
                  {
                     if(!options.funcRename) options.funcRename = { };
                     m = options.funcRename;
                  }
                  if(m)
                  {
                     while(next)
                     {
                        char * item = next + 1;
                        next = strchr(item, ',');
                        if(next) *next = 0;
                        if(*item)
                        {
                           char * val = strchr(item, '=');
                           if(val)
                           {
                              MapIterator<String, String> i { map = m };
                              *val = 0;
                              if(!i.Index(item, true))
                                 i.data = CopyString(++val);
                              else
                                 PrintLn($"Warning: map key '", item, "' is already specified!"); // todo: fix i18n
                           }
                           else
                              PrintLn($"Warning: map item '", item, "' is missing equal sign and will be ignored!"); // todo: fix i18n
                        }
                     }
                  }
               }
               else
               {
                  err = unknown;
                  PrintLn($"Error: argument ", sym, " (", type, ") is not a know symbol mapping."); // todo: fix i18n
               }
               delete copy;
            }
            /*else if(prev == funcRename)
            {
               char * key, * s = strstr(arg, "=");
               if(s)
               {
                  MapIterator<String, String> i { map = m };
                  int len = s - arg;
                  key = new char[len + 1];
                  strncpy(key, arg, len);
                  key[len] = 0;
                  if(!i.Index(key, true))
                     i.data = CopyString(++s);
                  else
                     PrintLn("map error: key (", key, ") is already specified!");
                  delete key;
               }
            }*/
            else
            {
               sym = null;
               if(prev == language)
               {
                  sym = nsym;
                  switch(sym)
                  {
                     case C:
                     case CPlusPlus:
                     case CSharp:
                     case Java:
                     case Python:
                        lang = (Language)sym;
                        dir = addDirectory("", null);
                        break;
                     default:
                        err = unknown;
                        PrintLn($"Error: argument ", sym, " (", arg, ") is not a know language."); // todo: fix i18n
                        break;
                  }
               }
               else if(prev == directory)
                  dir = addDirectory(arg, dir);
               else if(prev == string/* || prev == map*/)
               {
                  sym = (ArgSym)getSwitchSymbol(arg, scope);
                  /*if(prev == map && sym == ArgSym::funcRename)
                  {
                     m = null;
                     options = getOptions();
                     if(options)
                     {
                        if(!options.funcRename) options.funcRename = { };
                        m = options.funcRename;
                     }
                  }
                  else
                     conmsg("check"); // todo error*/
               }
               else if(prev == tell)
                  conmsg("check"); // todo
               else if(nextIsValidSymbol)
               {
                  sym = nsym;
                  switch(sym)
                  {
                     case C:
                     case CPlusPlus:
                     case CSharp:
                     case Java:
                     case Python:
                        //if(!lang)
                           lang = (Language)sym;
                           dir = addDirectory("", null);
                           //if(dir) dir.lang = lang;
                        /*else
                           err = langTwice;*/
                        break;
                     case quiet:
                        quiet = true;
                        break;
                     case about:
                     case help:
                     case examples:
                     case license:
                     case version:
                        if(!task)
                           task = bind;
                        else if(sym != bind)
                           err = taskTwice;
                        break;
                     case reset:
                        if(libs.count == 0)
                           error = unspecifiedLibBeforeReset;
                        else
                           generateGens();
                        break;
                     case all:
                     {
                        forAll = true;
                        break;
                     }
                     case string:
                     case map:
                        scope = sym;
                        break;
                     case tell:
                        break;
                     case directory:
                        break;
                     case ambiguous:
                        err = ambiguous;
                        PrintLn($"Error: argument ", sym, " (", arg, ") is ambiguous."); // todo: fix i18n
                        break;
                     case null:
                        err = unknown;
                        PrintLn($"Error: argument ", sym, " (", arg, ") is unknown."); // todo: fix i18n
                        break;
                     default: conmsg("check"); break;
                  }
                  switch(err)
                  {
                     case null:
                        break;
                     case taskTwice:
                     case langTwice:
                        if(!error) error = err;
                        break;
                     case ambiguous:
                     case outOfScope:
                     case unknown:
                        if(!argError) argError = err;
                        break;
                     default: conmsg("check"); break;
                  }
               }
               else if(task == bind)
                  lib = addLibrary(arg);
               if(c + 1 == argc && (sym == bind || sym == directory || sym == string || sym == map || sym == tell))
               {
                  if(!error) error = missing;
                  PrintLn($"Error: argument for ", sym, " (", arg, ") is missing."); // todo: fix i18n
                  /*if(sym == bind)
                     ;
                  else if(sym == directory)
                     ;
                  else if(sym == string)
                     ;
                  else if(sym == map)
                     ;
                  else if(sym == tell)
                     ;*/
               }
            }
         }
      }
      if(libs.count == 0)
      {
         if(gens.count == 0)
            error = mustSpecifyLib;
         else
            error = unspecifiedAdditionalLib;
      }
      if(error || argError) task = help;
      else if(task == bind/* || task == tell?*/)
         generateGens();
      if(error || argError)
      {
         if(error == mustSpecifyLib)
            PrintLn($"Error: at least one library must be specified for bgen to generate bindings.");
         else if(error == unspecifiedLibBeforeReset)
            PrintLn($"Error: at least one library must be specified before the 'reset' switch.");
         else if(error == unspecifiedAdditionalLib)
            PrintLn($"Error: although some library(ies) have been specified, no additional library(ies) have been specified after the 'reset' switch.");
         else if(error == taskTwice)
            PrintLn($"Error: you can only specify one task at a time.");
         else if(error == langTwice)
            PrintLn($"Error: you can only specify one target language at a time.");
         else if(!argError && error != missing)
            PrintLn($"Error: ", error);
         PrintLn($"Please follow appropriate syntax.");
         PrintLn("");
         idnt = "  ";
      }
      else if(gens.count)
      {
         for(gen : gens)
         {
            Gen g = this.gen = gen; // for watches
            //bool plug = false;
            // todo: fix this, python should not pollute c or globals
            python = (gen.lang == Python); // todo
            py = false; // todo
            g_ = (CGen)g;
            // tocheck: just drop?
            /*if(!g.lib.outputDir)
               g.lib.outputDir = CopyString(def.lib.outputDir);*/
            //g.lib.init();
            //PrintLn("doing: ", g.dir.lang, " - ", g.lib.bindingName, " -> ", g.dir.outputDir);
            if(g.lib.name)
            {
               GenOptions options = g.lib.readOptionsFile();
               if(options)
                  g.lib.options = options;
               if(!g.lib.options)
                  g.lib.options = optionsForAll;
               if(!g.lib.options)
                  g.lib.options = addOptions();
               if(g.init())
               {
                  // todo: add this as a 'tell' option, for generating complete lists from libs
                  //g.outLists();
                  g.process();
                  g.generate();
                  if(g.lib.verbose)
                     g.printOutputFiles();
               }
               /*if(plug)
                  g.lib.funcRename = null;*/
               g.reset();
               delete g;
            }
         }
      }

      /*if(def.funcRename)
      {
         MapIterator<String, String> i { map = def.funcRename };
         PrintLn("---------------------");
         while(i.Next())
         {
            PrintLn(i.key, " -> ", i.data);
         }
         PrintLn("---------------------");
      }*/

      // command-line options to select
      //
      //  - <input library>     // path/to/ecereCOM.dll or .so or just ecereCOM.dll or .so or just ecereCOM
      //     - [binding name]   // same as name part of input library if not specified (ecereCOM)
      //     - [define prefix]  // all uppercase version of binding name if not specified (ECERECOM)
      //  - [target language] (defaults to C) caseInsensitive(c|c89|cpp|c++|c#|csharp|java|python|py)
      //  - [output directory] (default to current)
      //  - generating (mangling) options
      //     - global prefix
      //     - name spaces
      //     - context-sensitive enumerations prefixes
      //  - ? other useful options ?
      onTask(task);

      //PrintLn("");
      //ad.printAllSpecs();
   }

   Directory addDirectory(const char * path, Directory preset)
   {
      if(preset && preset.lang == lang)
      {
         delete preset.outputDir;
         preset.outputDir = CopyString(path);
         preset.init();
         return preset;
      }
      else
      {
         Directory dir { };
         if(lang)
            dir.lang = lang;
         dir.outputDir = CopyString(path);
         dir.init();
         dirs.Add(dir);
         ownDirs.Add(dir);
         return dir;
      }
   }

   Library addLibrary(const char * name)
   {
      Library lib = createLibrary(name);
      libs.Add(lib);
      ownLibs.Add(lib);
      return lib;
   }

   GenOptions addOptions()
   {
      GenOptions options { };
      ownOptions.Add(options);
      return options;
   }

   GenOptions getOptions()
   {
      GenOptions options = null;
      if(forAll)
      {
         if(!optionsForAll)
            optionsForAll = addOptions();
         options = optionsForAll;
      }
      else
      {
         if(lib)
         {
            if(!lib.options)
               lib.options = addOptions();
            options = lib.options;
         }
         else
            PrintLn("options error: a library must be specified first!");
      }
      return options;
   }

   Gen addGen(Library lib, Directory dir)
   {
      Gen gen = null;
      python = false; // todo
      switch(dir.lang)
      {
         case C:           gen = CGen { };      break;
         case CPlusPlus:   gen = CPPGen { };    break;
         case CSharp:      gen = CSharpGen { }; break;
         case Java:        gen = JavaGen { };   break;
         case Python:
            python = true; // todo
                           gen = PythonGen { }; break;
         default: conmsg("check"); break;
      }
      gen.quiet = quiet;
      gen.lib = lib;
      gen.dir = dir;
      //if(def.lib.outputDir)
      //   gen.lib.outputDir = CopyString(def.lib.outputDir);
      gens.Add(gen);
      return gen;
   }

   void generateGens()
   {
      if(libs.count)
      {
         if(!dirs.count)
            dir = addDirectory("", null);
         for(dir : dirs)
         {
            for(lib : libs)
            {
               if(!cpath && dir.lang == C)
                  cpath = CopyString(dir.dir);
               addGen(lib, dir);
            }
         }
      }
      lang = null;
      forAll = false;
      libs.RemoveAll();
      dirs.RemoveAll();
   }

   //bool onArgCustom(int symbol) { return true; }
   //bool onArg(const char * arg, int pos, S symbol, S scope, S prev, E error, bool raw)
   //bool onArg(const char * arg, int pos, int symbol, int scope, int prev, int error, bool raw)
   bool onArg(const char * arg, int pos, ArgSym symbol, ArgSym scope, ArgSym prev, ArgErr error, bool raw)
   {
      if(raw)
      {
         if(prev == bind)
            conmsg("check");//gens.Add(createGen(null, arg, def)); // todo if onArg is ever used
         else if(prev == directory)
         {
            conmsg("check"); // todo?
            /*delete def.lib.outputDir;
            def.lib.outputDir = CopyString(arg);*/
         }
         else if(prev == string)
            conmsg("check"); // todo
         else if(prev == map)
            conmsg("check"); // todo
         else if(prev == tell)
            conmsg("check"); // todo
      }
      else
      {
      }
      return false;
   }

   bool onTask(int symbol)
   {
      ArgSym task = (ArgSym)symbol;
      if(task == about)
      {
         PrintLn("Language Binding Generator for eC Libraries (bgen)");
         PrintLn("Copyright (C) 2016-2018 Ecere Corporation");
         PrintLn("This software is distributed under a BSD 3-Clause (Revised) license.");
         return true;
      }
      else if(task == license)
      {
         PrintLn("BSD 3-Clause (Revised)");
         return true;
      }
      else if(task == version)
      {
         PrintLn("0.1 alpha");
         return true;
      }
      else if(task == examples)
      {
         idnt = "  ";
         PrintLn($"Examples:");
         PrintLn(idnt, $"'bgen \"C:\\Program Files\\Ecere\\bin\\ecere.dll\"'");
         PrintLn(idnt, $"'bgen ecereCOM'");
         PrintLn(idnt, $"'bgen ecere'");
         PrintLn(idnt, $"'bgen /usr/lib/libecere.so'");
         return true;
      }
      else if(task == help)
      {
         Print(
           $"Syntax:\n"
            "   bgen [global-options] [<global-language> [language-options]]*\n"
            "        [<library> [library-options] [<language> [library-language-options]]*]+\n"
            "\n"
            "   library:   library for which bindings will be generated\n"
            "              examples: foo, foo.dll, libfoo.so, /path/to/libfoo.so\n"
            "\n"
            "   languages: language for which to output bindings (case insensitive) any of:\n"
            "      C      (c, c89)                       (default) \n"
            "      C++    (cpp, cxx, cplusplus, c++)\n"
            "      C#     (c#, cs, csharp)\n"
            "      Java   (java)\n"
            "      Python (py, python)\n"
            "\n"
            "   Options:\n"
            "     -h                Shows this syntax help\n"
            "\n"
            "     -e                Shows some examples\n"
            "\n"
            "     -a                Shows program information\n"
            "\n"
            "     -v                Shows version information\n"
            "\n"
            "     -d <directory>    Specify output directory (default: current directory)\n"
            "\n"
            "     -q                Force bgen to execute silently\n"
            "\n"
            //"   --enum-prefix <prefix><string>        Prefix enumeration types by 'prefix'\n"
            //"\n"
            "     -m fren[,<oldname>=<newname>]+     Use an alternate name for a function\n"
            // "     -fren <key>=<value>[,<key>=<value>]*     Rename a function\n"
            "\n"
            //"   -tell <telltype>                     Tell you something\n"
            //"                        where telltype is something\n"
            //"\n"
            "     --black-list      Output all constructs within library for a blacklist\n"
            "                       (or whitelist) to ./<libname>.bgen.econ,\n"
            "                       only if file doesn't exist\n"
            "\n"
            "     --force-list      Output all constructs within library for a blacklist\n"
            "                       (or whitelist) to ./<libname>.bgen.econ,\n"
            "                       overwriting an existing file\n"
            "\n"
            "     --clear-all       Clear all options\n"
            "                       (e.g. to generate again with different options)\n"
            "\n"
            "     --clear-languages Clear all languages options\n"
            "\n"
            "     --clear-libraries Clear all libraries options\n"
            "\n"
            "     --clear-matrix    Clear all libraries & languages options\n"
            "\n"
            "     --bypass-macros   Bypass macros option (used by bgen/cpp)\n"
            "\n"
            "   Notes:\n"
            "      All switches are case insensitive.\n"
            "      The use of - or -- is optional for all switches.\n"
            "      All non-ambiguous truncated shorthand are accepted for all switches.\n"
         );

#if 0
         PrintLn(idnt, $"for examples the help switch can be specified in any of these ways");
         PrintLn(idnt, $"    'bgen -h' or 'bgen --he' or 'bgen --help' or 'bgen h' or 'bgen he' or 'bgen hel' or 'bgen help'");
         PrintLn(idnt, $"    'bgen -H' or 'bgen --HE' or 'bgen --HeLP' or 'bgen H' or 'bgen hE' or 'bgen hEl' or 'bgen Help'");
#endif // 0
         return true;
      }
      return false;
   }

   BGen()
   {
#ifdef _DEBUG
      dbglog_open(true);
#endif
   }

   ~BGen()
   {
      ownLibs.Free();
      ownDirs.Free();
      ownOptions.Free();
      gens.RemoveAll();
#ifdef _DEBUG
      dbglog_close();
#endif
   }
}

define app = ((BGen)__thisModule);
CGen g_;
bool python; // todo
bool py;
