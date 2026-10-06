#!/bin/sh
# platform: macOS-only -- assembles x86_64 Mach-O
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"
[ $# -eq 2 ] || { echo "usage: sh build/gen-trampolines.sh SYMLIST OUTDIR -- writes OUTDIR/fwd-<i>.o per name, OUTDIR/fwd-resolve.o and OUTDIR/symbols.txt" >&2; exit 2; }
symlist="$1"; out="$2"
[ -s "$symlist" ] || { echo "gen-trampolines: $symlist is empty or missing" >&2; exit 1; }
if [ -z "${SDK:-}" ]; then
  SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
fi
flags="-isysroot $SDK -mmacosx-version-min=10.9"
mkdir -p "$out"
list="$(mktemp "$out/.symbols.XXXXXX")"
trap 'rm -f "$list"' EXIT
cp "$symlist" "$list"
rm -f "$out"/fwd-*.s "$out"/fwd-*.o

i=0
while IFS= read -r sym; do
  [ -n "$sym" ] || continue
  n="${sym#_}"
  [ "_$n" = "$sym" ] || { echo "gen-trampolines: $sym in $symlist is not a Mach-O name (no leading _)" >&2; exit 1; }
  case "$n" in
    *[!A-Za-z0-9_\$.]*) echo "gen-trampolines: $sym holds a character the generated assembly cannot carry" >&2; exit 1 ;;
  esac
  i=$((i + 1))
  s="$out/fwd-$i.s"
  sed -e "s/@N@/$n/g" > "$s" <<'ASM'
	.section	__TEXT,__text,regular,pure_instructions
	.globl	"_@N@"
	.p2align	4, 0x90
"_@N@":
	cmpq	$0, "___recaulk_slot_@N@"(%rip)
	je	Lresolve
	jmpq	*"___recaulk_slot_@N@"(%rip)
Lresolve:
	pushq	%rbp
	movq	%rsp, %rbp
	subq	$336, %rsp
	movq	%rdi, 0(%rsp)
	movq	%rsi, 8(%rsp)
	movq	%rdx, 16(%rsp)
	movq	%rcx, 24(%rsp)
	movq	%r8, 32(%rsp)
	movq	%r9, 40(%rsp)
	movq	%rax, 48(%rsp)
	movq	%r10, 56(%rsp)
	movq	%r11, 64(%rsp)
	movdqu	%xmm0, 80(%rsp)
	movdqu	%xmm1, 96(%rsp)
	movdqu	%xmm2, 112(%rsp)
	movdqu	%xmm3, 128(%rsp)
	movdqu	%xmm4, 144(%rsp)
	movdqu	%xmm5, 160(%rsp)
	movdqu	%xmm6, 176(%rsp)
	movdqu	%xmm7, 192(%rsp)
	movdqu	%xmm8, 208(%rsp)
	movdqu	%xmm9, 224(%rsp)
	movdqu	%xmm10, 240(%rsp)
	movdqu	%xmm11, 256(%rsp)
	movdqu	%xmm12, 272(%rsp)
	movdqu	%xmm13, 288(%rsp)
	movdqu	%xmm14, 304(%rsp)
	movdqu	%xmm15, 320(%rsp)
	leaq	Lname(%rip), %rdi
	leaq	"___recaulk_impl_@N@"(%rip), %rsi
	leaq	"___recaulk_slot_@N@"(%rip), %rdx
	callq	"___recaulk_resolve"
	movdqu	80(%rsp), %xmm0
	movdqu	96(%rsp), %xmm1
	movdqu	112(%rsp), %xmm2
	movdqu	128(%rsp), %xmm3
	movdqu	144(%rsp), %xmm4
	movdqu	160(%rsp), %xmm5
	movdqu	176(%rsp), %xmm6
	movdqu	192(%rsp), %xmm7
	movdqu	208(%rsp), %xmm8
	movdqu	224(%rsp), %xmm9
	movdqu	240(%rsp), %xmm10
	movdqu	256(%rsp), %xmm11
	movdqu	272(%rsp), %xmm12
	movdqu	288(%rsp), %xmm13
	movdqu	304(%rsp), %xmm14
	movdqu	320(%rsp), %xmm15
	movq	0(%rsp), %rdi
	movq	8(%rsp), %rsi
	movq	16(%rsp), %rdx
	movq	24(%rsp), %rcx
	movq	32(%rsp), %r8
	movq	40(%rsp), %r9
	movq	48(%rsp), %rax
	movq	56(%rsp), %r10
	movq	64(%rsp), %r11
	leave
	jmpq	*"___recaulk_slot_@N@"(%rip)

	.section	__TEXT,__cstring,cstring_literals
Lname:
	.asciz	"@N@"

	.section	__DATA,__data
	.private_extern	"___recaulk_slot_@N@"
	.p2align	3
"___recaulk_slot_@N@":
	.quad	0

	.subsections_via_symbols
ASM
  /usr/bin/clang $flags -arch x86_64 -c "$s" -o "$out/fwd-$i.o"
done < "$list"

/usr/bin/clang $flags -arch x86_64 -Os -fPIC -Wall -c "$MAVERICKS_ROOT/src/forward/resolve.c" -o "$out/fwd-resolve.o"
mv -f "$list" "$out/symbols.txt"
