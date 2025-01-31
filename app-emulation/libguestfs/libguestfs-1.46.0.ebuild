# Copyright 1999-2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

LUA_COMPAT=( lua5-1 )
PYTHON_COMPAT=( python3_{8,9,10} )

inherit autotools bash-completion-r1 linux-info lua-single perl-functions python-single-r1 strip-linguas toolchain-funcs xdg-utils flag-o-matic

MY_PV_1="$(ver_cut 1-2)"
MY_PV_2="$(ver_cut 2)"
[[ $(( ${MY_PV_2} % 2 )) -eq 0 ]] && SD="stable" || SD="development"

DESCRIPTION="Tools for accessing, inspect  and modifying virtual machine (VM) disk images"
HOMEPAGE="https://libguestfs.org/"
SRC_URI="https://libguestfs.org/download/${MY_PV_1}-${SD}/${P}.tar.gz"

LICENSE="GPL-2 LGPL-2"
SLOT="0/${MY_PV_1}"

KEYWORDS="~amd64"
IUSE="doc erlang +fuse gtk inspect-icons introspection libvirt lua +ocaml +perl python ruby selinux static-libs systemtap test"
RESTRICT="!test? ( test )"

REQUIRED_USE="lua? ( ${LUA_REQUIRED_USE} )
	python? ( ${PYTHON_REQUIRED_USE} )"

# Failures - doc

# FIXME: selinux support is automagic
COMMON_DEPEND="
	sys-libs/ncurses:0=
	sys-devel/gettext
	>=app-misc/hivex-1.3.1
	dev-libs/libpcre:3
	app-arch/cpio
	dev-lang/perl:=
	app-cdr/cdrtools
	>=app-emulation/qemu-2.0[qemu_softmmu_targets_x86_64,systemtap?,selinux?,filecaps]
	sys-apps/fakeroot
	sys-apps/file
	libvirt? ( app-emulation/libvirt )
	dev-libs/libxml2:2=
	>=sys-apps/fakechroot-2.8
	>=app-admin/augeas-1.8.0
	sys-fs/squashfs-tools:*
	dev-libs/libconfig:=
	dev-libs/jansson:=
	sys-libs/readline:0=
	>=sys-libs/db-4.6:*
	app-arch/xz-utils
	app-arch/lzma
	app-crypt/gnupg
	app-arch/unzip[natspec]
	perl? (
		virtual/perl-ExtUtils-MakeMaker
		>=dev-perl/Sys-Virt-0.2.4
		virtual/perl-Getopt-Long
		virtual/perl-Data-Dumper
		dev-perl/libintl-perl
		>=app-misc/hivex-1.3.1[perl?]
		dev-perl/String-ShellQuote
	)
	python? ( ${PYTHON_DEPS} )
	fuse? ( sys-fs/fuse:= )
	introspection? (
		>=dev-libs/glib-2.26:2
		>=dev-libs/gobject-introspection-1.30.0:=
	)
	selinux? (
		sys-libs/libselinux
		sys-libs/libsemanage
	)
	systemtap? ( dev-util/systemtap )
	ocaml? ( >=dev-lang/ocaml-4.03:=[ocamlopt] )
	erlang? ( dev-lang/erlang )
	inspect-icons? (
		media-libs/netpbm
		media-gfx/icoutils
	)
	virtual/acl
	sys-libs/libcap
	lua? ( ${LUA_DEPS} )
	>=dev-libs/yajl-2.0.4
	gtk? (
		sys-apps/dbus
		x11-libs/gtk+:3
	)
	net-libs/libtirpc:=
	sys-libs/libxcrypt:=
"
# Some OCaml is always required
# bug #729674
DEPEND="${COMMON_DEPEND}
	dev-util/gperf
	>=dev-lang/ocaml-4.03:=[ocamlopt]
	dev-ml/findlib[ocamlopt]
	ocaml? (
		dev-ml/ounit2[ocamlopt]
		|| (
			<dev-ml/ocaml-gettext-0.4.2
			dev-ml/ocaml-gettext-stub[ocamlopt]
		)
	)
	doc? ( app-text/po4a )
	ruby? ( dev-lang/ruby virtual/rubygems dev-ruby/rake )
	test? ( introspection? ( dev-libs/gjs ) )
"
BDEPEND="virtual/pkgconfig"
RDEPEND="${COMMON_DEPEND}
	app-emulation/libguestfs-appliance
"
# Upstream build scripts compile and install Lua bindings for the ABI version
# obtained by running 'lua' on the build host
BDEPEND="lua? ( ${LUA_DEPS} )"

DOCS=( AUTHORS BUGS ChangeLog HACKING README TODO )

#PATCHES=(
#	"${FILESDIR}"/${MY_PV_1}/
#)

pkg_setup() {
	CONFIG_CHECK="~KVM ~VIRTIO"
	[[ -n "${CONFIG_CHECK}" ]] && check_extra_config

	use lua && lua-single_pkg_setup
	use python && python-single-r1_pkg_setup
}

src_prepare() {
	default
	xdg_environment_reset
	eautoreconf
}

src_configure() {
	# bug #794877
	tc-export AR

	# Skip Bash test
	# (See 13-test-suite.log in linked bug)
	# bug #794874
	export SKIP_TEST_COMPLETE_IN_SCRIPT_SH=1

	# Disable feature test for kvm for more reason
	# i.e: not loaded module in __build__ time,
	# build server not supported kvm, etc. ...
	#
	# In fact, this feature is virtio support and requires
	# configured kernel.
	export vmchannel_test=no

	# Give a nudge to help find libxcrypt[-system]
	# bug #703118, bug #789354
	append-ldflags "-L${ESYSROOT}/usr/$(get_libdir)/xcrypt"
	append-ldflags "-Wl,-R${ESYSROOT}/usr/$(get_libdir)/xcrypt"

	econf \
		$(use_with libvirt) \
		--disable-appliance \
		--disable-daemon \
		--with-extra="-gentoo" \
		--with-readline \
		--disable-php \
		$(use_enable python) \
		--without-java \
		$(use_enable perl) \
		$(use_enable fuse) \
		$(use_enable ocaml) \
		$(use_enable ruby) \
		--disable-haskell \
		--disable-golang \
		--disable-rust \
		$(use_enable introspection gobject) \
		$(use_enable introspection) \
		$(use_enable erlang) \
		$(use_enable static-libs static) \
		$(use_enable systemtap probes) \
		$(use_enable lua) \
		$(usex doc '' PO4A=no)
}

src_install() {
	strip-linguas -i po

	emake DESTDIR="${D}" install "LINGUAS=""${LINGUAS}"""

	find "${ED}" -name '*.la' -delete || die

	if use perl ; then
		perl_delete_localpod

		# Workaround Build.PL for now
		doman "${ED}"/usr/man/man3/Sys::Guestfs.3pm
		rm -rf "${ED}"/usr/man || die
	fi
}

pkg_postinst() {
	if ! use gtk ; then
		einfo "virt-p2v NOT installed"
	fi

	if ! use ocaml ; then
		einfo "OCaml based tools and bindings (virt-resize, virt-sparsify, virt-sysprep, ...) NOT installed"
	fi

	if ! use perl ; then
		einfo "Perl based tools NOT built"
	fi
}
