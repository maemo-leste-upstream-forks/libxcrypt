# Generate macros that control the symbol versions of the public
# library API, from a .map.in file.
#
# Written by Zack Weinberg <zackw at panix.com> in 2017.
# To the extent possible under law, Zack Weinberg has waived all
# copyright and related or neighboring rights to this work.
#
# See https://creativecommons.org/publicdomain/zero/1.0/ for further
# details.

# The .map.in file is the first input file, and we expect the Makefile
# to have set the variables SYMVER_MIN, SYMVER_FLOOR, and COMPAT_ABI.
# See libcrypt.map.in and gen-vers.awk for explanations of the format
# of .map.in files.  See crypt-port.h for an explanation of how to use
# the macros generated by this program.
#
# Note: if you change the format of .map.in files you probably need to
# update gen-map.awk too.
#
# Note: we currently don't support compatibility symbols that need
# a different definition from the default version.

BEGIN {
    split("", SYMBOLS) # ensure SYMBOLS is an array
    split("", VCHAIN)  # ditto VCHAIN
    NVCHAIN = 0

    # This arranges for sorted output if gawk is in use, and is
    # harmless otherwise.
    PROCINFO["sorted_in"] = "@ind_str_asc"
}

NF == 0   { next } # blank line, discard
$1 == "#" { next } # comment, discard
$1 == "%chain" {
    for (i = 2; i <= NF; i++) {
        VCHAIN[++NVCHAIN] = $i
    }
    next
}

{
    if ($2 == "-") {
        compat_only[$1] = 1
    } else {
        compat_only[$1] = 0
        if ($2 in SYMBOLS) {
            SYMBOLS[$2] = SYMBOLS[$2] SUBSEP $1
        } else {
            SYMBOLS[$2] = $1
        }
    }
    for (i = 3; i <= NF; i++) {
        sym=$i
        n=split(sym, a, ":")
        if (n > 1) {
            sym=""
            for (j = 2; j <= n; j++) {
                if (COMPAT_ABI == "yes" || COMPAT_ABI == a[j]) {
                    sym=a[1]
                }
            }
        }
        if (sym != "") {
            if (sym in SYMBOLS) {
                SYMBOLS[sym] = SYMBOLS[sym] SUBSEP $1
            } else {
                SYMBOLS[sym] = $1
            }
        }
    }
}

END {
    if (NVCHAIN == 0) {
        print ARGV[1] ": error: missing %chain directive" > "/dev/stderr"
        close("/dev/stderr")
        exit 1
    }
    symver_min_idx = 0
    symver_floor_idx = 0
    for (i = 1; i <= NVCHAIN; i++) {
        if (VCHAIN[i] == SYMVER_MIN) {
            symver_min_idx = i
        }
        if (VCHAIN[i] == SYMVER_FLOOR) {
            symver_floor_idx = i
        }
    }
    if (symver_min_idx == 0) {
        print ARGV[1] ": error: SYMVER_MIN (" SYMVER_MIN ") " \
            "not found in %chain directives" > "/dev/stderr"
        close("/dev/stderr")
        exit 1
    }
    if (symver_floor_idx == 0) {
        print ARGV[1] ": error: SYMVER_FLOOR (" SYMVER_FLOOR ") " \
            "not found in %chain directives" > "/dev/stderr"
        close("/dev/stderr")
        exit 1
    }
    if (symver_floor_idx < symver_min_idx) {
        print ARGV[1] ": error: SYMVER_FLOOR (" SYMVER_FLOOR ") " \
            "is lower than SYMVER_MIN (" SYMVER_MIN ")" > "/dev/stderr"
        close("/dev/stderr")
        exit 1
    }

    # Construct a pruned set of symbols and versions, including only
    # versions with symbols, discarding all symbols associated with
    # versions below SYMVER_MIN, raising symbols below SYMVER_FLOOR to
    # SYMVER_FLOOR, and removing duplicates.
    # Note: unlike in gen-map.awk, symbols all of whose versions are
    # below SYMVER_MIN must still be counted in 'allsyms' so their
    # INCLUDE macros are generated.
    for (i = 1; i <= NVCHAIN; i++) {
        v = VCHAIN[i]
        if (v in SYMBOLS) {
            nsyms = split(SYMBOLS[v], syms, SUBSEP)
            j = i;
            if (j < symver_floor_idx)
                j = symver_floor_idx;
            vr = VCHAIN[j]
            for (s = 1; s <= nsyms; s++) {
                if (syms[s]) {
                    allsyms[syms[s]] = 1
                    if (i >= symver_min_idx) {
                        symset[vr, syms[s]] = 1
                    }
                }
            }
        }
    }

    print "/* Generated from " ARGV[1] " by gen-vers.awk.  DO NOT EDIT.  */"
    print ""
    print "#ifndef _CRYPT_SYMBOL_VERS_H"
    print "#define _CRYPT_SYMBOL_VERS_H 1"

    print ""
    print "/* For each public symbol <sym>, INCLUDE_<sym> is true if it"
    print "   has any versions above the backward compatibility minimum."
    print "   Compatibility-only symbols are not included in the static"
    print "   library, or in the shared library when configured with"
    print "   --disable-obsolete-api.  */"
    print "#if defined PIC && ENABLE_OBSOLETE_API"
    print ""
    for (sym in allsyms) {
        include = 0
        for (i = symver_floor_idx; i <= NVCHAIN; i++) {
            if ((VCHAIN[i], sym) in symset) {
                include++
            }
        }
        includesym[sym] = include
        printf("#define INCLUDE_%s %d\n", sym, include)
    }
    print ""
    print "#else"
    print ""
    for (sym in allsyms) {
        printf("#define INCLUDE_%s %d\n", sym,
               (includesym[sym] && !compat_only[sym]))
    }
    print ""
    print "#endif"

    print ""
    print "/* For each public symbol <sym> that is included, define its"
    print "   highest version as the default, and aliases at each"
    print "   compatibility version. */"

    for (sym in allsyms) {
        if (includesym[sym]) {
            seq = 0
            for (i = NVCHAIN; i >= symver_floor_idx; i--) {
                v = VCHAIN[i]
                if ((v, sym) in symset) {
                    if (seq == 0) {
                        if (compat_only[sym] || includesym[sym] > 1) {
                            printf("#ifdef PIC\n#define %s _crypt_%s\n#endif\n",
                                   sym, sym);
                        }
                        printf("#define SYMVER_%s \\\n", sym)
                        if (compat_only[sym]) {
                            printf("  symver_compat0 (\"%s\", %s, %s)", sym, sym, v)
                        } else if (includesym[sym] > 1) {
                            printf("  symver_default (\"%s\", %s, %s)", sym, sym, v)
                        } else {
                            # Due to what appears to be a bug in GNU ld,
                            # we must not issue symver_default() if there
                            # aren't going to be any other versions.
                            printf("  symver_nop ()")
                        }
                    } else {
                        printf("; \\\n  symver_compat (%d, \"%s\", %s, %s, %s)",
                               seq, sym, sym, sym, v)
                    }
                    seq++
                }
            }
            print ""
        } else {
            printf("#define SYMVER_%s symver_nop()\n", sym)
        }
    }


    print ""
    print "#endif /* crypt-symbol-vers.h */"
}
