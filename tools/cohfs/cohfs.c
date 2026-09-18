/*
 * cohfs -- make, read and write COHERENT filesystems inside a disk image.
 *
 *	cohfs mkfs   -p BLK IMAGE FSIZE ISIZE STAGEDIR
 *	cohfs ls     [-p BLK] IMAGE PATH
 *	cohfs cat    [-p BLK] IMAGE PATH
 *	cohfs find   [-p BLK] IMAGE PATH
 *	cohfs blocks [-p BLK] IMAGE PATH
 *	cohfs put    -p BLK [-m MODE] IMAGE HOSTFILE GUESTPATH...
 *	cohfs parts  [-p BLK] IMAGE
 *
 * -p names the block at which the filesystem's partition starts in IMAGE.
 * The readers without it try every filesystem `parts' finds and use the first
 * that has PATH, since the boot partition is first in a disk image and is
 * almost never the one wanted.
 *
 * ls prints `mode size inode name' for PATH, or for each entry of it if it is
 * a directory.  find prints `mode nlink uid gid size inode rdev path' for PATH
 * and everything under it, depth first in directory order, where rdev is
 * `major,minor' for a device and `-' otherwise; a directory reached twice is
 * listed and not entered again.  blocks prints PATH's data block numbers, one
 * a line, relative to the partition.  parts prints `start fsize isize tfree
 * tinode' for every filesystem in IMAGE, or for the one at -p, and fails if
 * there is none there.  A filesystem is found at ANY block, not only at a
 * multiple of eight: hd42-coh.media starts /usr at 44105.
 *
 * mkfs writes a filesystem of FSIZE blocks with ISIZE blocks of boot block,
 * superblock and inode table, holding the tree at STAGEDIR, into IMAGE at the
 * partition's start.  The file is created if it is not there and grown if it
 * is short; nothing outside the partition's FSIZE blocks is touched, and every
 * block inside it is written, so the result does not depend on what IMAGE held
 * before.  A staging tree cannot carry ownership or device nodes, so its root
 * may hold two manifests, which are read and not copied:
 *
 *	MANIFEST	<path> <octal-mode> <uid> <gid>
 *	DEVICES		<path> <b|c> <octal-mode> <major> <minor> [<uid> <gid>]
 *
 * An entry not named in MANIFEST is uid 0, gid 1, mode 755 for a directory or
 * an executable and 644 otherwise.  Two staged names that are one host file
 * (a hard link) are one inode, which is the only way a V7 filesystem gives a
 * file two names.  Allocation is in walk order -- names sorted, each
 * directory's files before its own data, subdirectories after -- and every
 * time field is one constant, so the same tree makes the same bytes.
 *
 * On Windows a hard link is recognised by volume and file index, since stat()
 * there reports one link and no inode for every file, and standard output is
 * binary, so `cat' copies a program exactly and a line ends as it does
 * everywhere else.  NTFS has no execute
 * bit, so a staged program is 644 there unless MANIFEST names its mode.
 *
 * put replaces a file's contents, keeping its mode unless -m is given, or
 * creates it in a directory that exists (mode 644 unless -m).  The old data
 * blocks are leaked; this is for scratch images that are booted and thrown
 * away, not for filesystems that are kept.
 *
 * THE FORMAT (include/sys/filsys.h, ino.h, fblk.h, dir.h).  512-byte blocks.
 * Block 1 of a partition is the superblock; inodes are 64 bytes from block 2,
 * inode 1 is the bad-block file and 2 the root.  16-bit fields are little-
 * endian and 32-bit ones PDP order, high word first.  An inode holds 13 block
 * addresses packed in three bytes each (10 direct, single, double and triple
 * indirect); an indirect block holds 128 four-byte addresses.  Free blocks
 * are a V7 chained stack of 64 per link, and the superblock caches up to 100
 * free inode numbers.  A directory entry is a 16-bit inode number and a
 * 14-byte name.
 */
#include <dirent.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <windows.h>
#define lstat	stat		/* no symbolic links to tell apart */
#endif

#define BS		512
#define NICFREE		64
#define NICINOD		100
#define INOSZ		64
#define BADFIN		1
#define ROOTIN		2
#define ND		10
#define NADDR		13
#define NBN		128		/* addresses in an indirect block */
#define DIRSIZ		14
#define DIRENT		16
#define STAMP		1784736000L	/* every time field; see mkfs above */

#define IFMT		0170000
#define IFDIR		0040000
#define IFCHR		0020000
#define IFBLK		0060000
#define IFREG		0100000

/* Superblock offsets. */
#define S_ISIZE		0
#define S_FSIZE		2
#define S_NFREE		6
#define S_FREE		8
#define S_NINODE	264
#define S_INODE		266
#define S_TIME		470
#define S_TFREE		474
#define S_TINODE	478
#define S_M		480
#define S_N		482
#define S_FNAME		484

/* Inode offsets. */
#define DI_MODE		0
#define DI_NLINK	2
#define DI_UID		4
#define DI_GID		6
#define DI_SIZE		8
#define DI_ADDR		12
#define DI_ATIME	52
#define DI_MTIME	56
#define DI_CTIME	60

static FILE *img;
static char *imgname;
static long base;			/* partition start, in blocks */
static long imgblocks;			/* blocks in IMAGE when it was opened */

static void
die(char *fmt, ...)
{
	va_list ap;

	fprintf(stderr, "cohfs: ");
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fprintf(stderr, "\n");
	exit(1);
}

static void *
xalloc(n)
size_t n;
{
	void *p;

	if ((p = calloc(n ? n : 1, 1)) == 0)
		die("out of memory");
	return p;
}

static void *
xgrow(p, n)
void *p;
size_t n;
{
	if ((p = realloc(p, n ? n : 1)) == 0)
		die("out of memory");
	return p;
}

static char *
xstrdup(s)
char *s;
{
	return strcpy(xalloc(strlen(s) + 1), s);
}

static unsigned long
get16(b, o)
unsigned char *b;
long o;
{
	return (unsigned long)b[o] | ((unsigned long)b[o + 1] << 8);
}

static unsigned long
get32(b, o)
unsigned char *b;
long o;
{
	return (get16(b, o) << 16) | get16(b, o + 2);
}

/* A packed block address is (high, low, middle): l3tol(). */
static unsigned long
getl3(b, o)
unsigned char *b;
long o;
{
	return ((unsigned long)b[o] << 16) | ((unsigned long)b[o + 2] << 8)
		| b[o + 1];
}

static void
put16(b, o, v)
unsigned char *b;
long o;
unsigned long v;
{
	b[o] = v & 0xFF;
	b[o + 1] = (v >> 8) & 0xFF;
}

static void
put32(b, o, v)
unsigned char *b;
long o;
unsigned long v;
{
	put16(b, o, (v >> 16) & 0xFFFF);
	put16(b, o + 2, v & 0xFFFF);
}

static void
putl3(b, o, v)
unsigned char *b;
long o;
unsigned long v;
{
	b[o] = (v >> 16) & 0xFF;
	b[o + 1] = v & 0xFF;
	b[o + 2] = (v >> 8) & 0xFF;
}

/* ---- the image -------------------------------------------------------- */

static void
openimg(name, mode)
char *name, *mode;
{
	long end;

	imgname = name;
	if ((img = fopen(name, mode)) == 0) {
		if (strcmp(mode, "r+b") != 0 || errno != ENOENT
		 || (img = fopen(name, "w+b")) == 0)
			die("%s: %s", name, strerror(errno));
	}
	if (fseek(img, 0L, SEEK_END) != 0 || (end = ftell(img)) < 0)
		die("%s: cannot seek", name);
	imgblocks = end / BS;
}

/* Block n of the partition.  Past the end of the file reads as zeroes. */
static void
rblk(n, b)
long n;
unsigned char *b;
{
	size_t got;

	memset(b, 0, BS);
	if (fseek(img, (base + n) * BS, SEEK_SET) != 0)
		die("%s: cannot seek to block %ld", imgname, base + n);
	got = fread(b, 1, BS, img);
	if (got < BS && ferror(img))
		die("%s: read error at block %ld", imgname, base + n);
}

static void
wblk(n, b)
long n;
unsigned char *b;
{
	if (fseek(img, (base + n) * BS, SEEK_SET) != 0
	 || fwrite(b, 1, BS, img) != BS)
		die("%s: write error at block %ld", imgname, base + n);
}

static void
closeimg()
{
	if (fflush(img) != 0 || ferror(img) || fclose(img) != 0)
		die("%s: write error", imgname);
}

static long
inoblk(ino)
long ino;
{
	return 2 + (ino - 1) / 8;
}

static long
inooff(ino)
long ino;
{
	return ((ino - 1) % 8) * INOSZ;
}

/* ---- reading ---------------------------------------------------------- */

struct fs {
	long isize, fsize;
};

struct ino {
	long num;
	unsigned long mode, nlink, uid, gid, size;
	unsigned long addr[NADDR];
};

static void
iget(num, ip)
long num;
struct ino *ip;
{
	unsigned char b[BS];
	int i;

	rblk(inoblk(num), b);
	ip->num = num;
	ip->mode = get16(b, inooff(num) + DI_MODE);
	ip->nlink = get16(b, inooff(num) + DI_NLINK);
	ip->uid = get16(b, inooff(num) + DI_UID);
	ip->gid = get16(b, inooff(num) + DI_GID);
	ip->size = get32(b, inooff(num) + DI_SIZE);
	for (i = 0; i < NADDR; i++)
		ip->addr[i] = getl3(b, inooff(num) + DI_ADDR + 3 * i);
}

/*
 * Every data block of a file, in order, into list[]; returns how many, stopping
 * once they cover `want' blocks.  A direct address of 0 is a hole and stands
 * for a block of zeroes; a 0 inside an indirect block is skipped.
 */
static long
iblocks(blk, depth, list, n, want)
unsigned long blk;
int depth;
unsigned long *list;
long n, want;
{
	unsigned char b[BS];
	unsigned long a;
	int i;

	if (blk == 0)
		return n;
	rblk((long)blk, b);
	for (i = 0; i < NBN && n < want; i++) {
		a = get32(b, 4 * i);
		if (a == 0)
			continue;
		if (depth == 1)
			list[n++] = a;
		else
			n = iblocks(a, depth - 1, list, n, want);
	}
	return n;
}

/* A file's contents; *lenp is set to its size. */
static unsigned char *
iread(ip, lenp)
struct ino *ip;
long *lenp;
{
	unsigned long *list;
	unsigned char *data, b[BS];
	long want, n, i, left, take;

	/* A size is 32 bits, and a long may be too: refuse one no image holds
	 * before it is used as a count. */
	if (ip->size > (unsigned long)imgblocks * BS)
		die("inode %ld: size %lu is more than the image holds", ip->num,
		    ip->size);
	want = ((long)ip->size + BS - 1) / BS;
	list = xalloc((size_t)(want + 1) * sizeof(*list));
	for (n = 0; n < ND && n < want; n++)
		list[n] = ip->addr[n];
	n = iblocks(ip->addr[ND], 1, list, n, want);
	n = iblocks(ip->addr[ND + 1], 2, list, n, want);
	n = iblocks(ip->addr[ND + 2], 3, list, n, want);
	data = xalloc((size_t)ip->size + 1);
	left = (long)ip->size;
	for (i = 0; i < n && left > 0; i++) {
		if (list[i])
			rblk((long)list[i], b);
		else
			memset(b, 0, BS);
		take = left < BS ? left : BS;
		memcpy(data + (ip->size - left), b, (size_t)take);
		left -= take;
	}
	free(list);
	*lenp = (long)ip->size - left;
	return data;
}

/* The inode `name' names in directory `dir', or 0. */
static long
dirlook(dir, name)
struct ino *dir;
char *name;
{
	unsigned char *d;
	long len, o, ino;

	d = iread(dir, &len);
	for (o = 0; o + DIRENT <= len; o += DIRENT) {
		ino = (long)get16(d, o);
		if (ino && strncmp((char *)d + o + 2, name, DIRSIZ) == 0
		 && (strlen(name) <= DIRSIZ)) {
			free(d);
			return ino;
		}
	}
	free(d);
	return 0;
}

/*
 * The inode `path' names, or 0 with *why set.  Empty components are skipped,
 * so `/', `' and `//etc/' all mean what they would to the kernel.
 */
static long
namei(path, why)
char *path, **why;
{
	struct ino ip;
	char comp[DIRSIZ + 2], *p, *e;
	long ino;
	size_t n;

	ino = ROOTIN;
	for (p = path; *p; p = e) {
		while (*p == '/')
			p++;
		if (*p == 0)
			break;
		for (e = p; *e && *e != '/'; e++)
			;
		n = e - p;
		iget(ino, &ip);
		if ((ip.mode & IFMT) != IFDIR) {
			*why = "not a directory";
			return 0;
		}
		if (n > DIRSIZ) {
			*why = "no such file or directory";
			return 0;
		}
		memcpy(comp, p, n);
		comp[n] = 0;
		if ((ino = dirlook(&ip, comp)) == 0) {
			*why = "no such file or directory";
			return 0;
		}
	}
	return ino;
}

/*
 * Whether a filesystem starts at `base': a superblock with a plausible s_isize
 * and an s_fsize that fits the image, over a root directory whose first two
 * entries are `.' and `..', both inode 2.  Every block of an image is asked,
 * so the test has to be one that data does not pass by accident.
 */
static int
isfs()
{
	unsigned char b[BS];
	struct ino root;
	unsigned long isize, fsize;

	if (base + 2 >= imgblocks)
		return 0;
	rblk(1L, b);
	isize = get16(b, S_ISIZE);
	fsize = get32(b, S_FSIZE);
	if (isize <= 2 || isize >= 2000 || fsize <= isize
	 || fsize > (unsigned long)(imgblocks - base))
		return 0;
	iget((long)ROOTIN, &root);
	if ((root.mode & IFMT) != IFDIR || root.nlink < 2
	 || root.size < 2 * DIRENT || root.addr[0] < isize
	 || root.addr[0] >= fsize)
		return 0;
	rblk((long)root.addr[0], b);
	return get16(b, 0L) == ROOTIN && strcmp((char *)b + 2, ".") == 0
	    && get16(b, (long)DIRENT) == ROOTIN
	    && strcmp((char *)b + DIRENT + 2, "..") == 0;
}

/* Every block at which a filesystem starts; the count, and list[] if given. */
static long
parts(list)
long *list;
{
	long n, save;

	save = base;
	n = 0;
	for (base = 0; base + 2 < imgblocks; base++)
		if (isfs()) {
			if (list)
				list[n] = base;
			n++;
		}
	base = save;
	return n;
}

static void
lsline(ip, name)
struct ino *ip;
char *name;
{
	printf("%6lo %8lu %5ld %s\n", ip->mode, ip->size, ip->num, name);
}

static void
findline(ip, path)
struct ino *ip;
char *path;
{
	unsigned long t;

	t = ip->mode & IFMT;
	printf("%lo %lu %lu %lu %lu %ld ", ip->mode, ip->nlink, ip->uid, ip->gid,
	       ip->size, ip->num);
	/*
	 * The dev word is the first two bytes of di_addr[0], minor then major,
	 * which the (high, low, middle) unpacking put in bits 16-23 and 0-7.
	 */
	if (t == IFCHR || t == IFBLK)
		printf("%lu,%lu ", ip->addr[0] & 0xFF, (ip->addr[0] >> 16) & 0xFF);
	else
		printf("- ");
	printf("%s\n", path);
}

/* Inodes of the directories already entered: a loop guard. */
static long *seen;
static long nseen, capseen;

static void
walk(ip, path)
struct ino *ip;
char *path;
{
	struct ino ce;
	unsigned char *d;
	char name[DIRSIZ + 1], *p;
	long len, o, i, ino;

	findline(ip, path);
	if ((ip->mode & IFMT) != IFDIR)
		return;
	for (i = 0; i < nseen; i++)
		if (seen[i] == ip->num)
			return;
	if (nseen == capseen)
		seen = xgrow(seen, (size_t)(capseen = capseen ? 2 * capseen : 64)
			     * sizeof(*seen));
	seen[nseen++] = ip->num;
	d = iread(ip, &len);
	for (o = 0; o + DIRENT <= len; o += DIRENT) {
		if ((ino = (long)get16(d, o)) == 0)
			continue;
		memcpy(name, d + o + 2, DIRSIZ);
		name[DIRSIZ] = 0;
		if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0)
			continue;
		p = xalloc(strlen(path) + strlen(name) + 2);
		sprintf(p, "%s%s%s", path,
			path[strlen(path) - 1] == '/' ? "" : "/", name);
		iget(ino, &ce);
		walk(&ce, p);
		free(p);
	}
	free(d);
}

static void
doread(cmd, path)
char *cmd, *path;
{
	struct ino ip, ce;
	unsigned long *list;
	unsigned char *d;
	char name[DIRSIZ + 1], *why;
	long ino, len, o, n, want;

	iget(namei(path, &why), &ip);
	if (strcmp(cmd, "cat") == 0) {
		d = iread(&ip, &len);
		if (fwrite(d, 1, (size_t)len, stdout) != (size_t)len)
			die("write error");
		free(d);
		return;
	}
	if (strcmp(cmd, "find") == 0) {
		walk(&ip, path);
		return;
	}
	if (strcmp(cmd, "blocks") == 0) {
		if (ip.size > (unsigned long)imgblocks * BS)
			die("inode %ld: size %lu is more than the image holds",
			    ip.num, ip.size);
		want = ((long)ip.size + BS - 1) / BS;
		list = xalloc((size_t)(want + 1) * sizeof(*list));
		for (n = 0; n < ND && n < want; n++)
			list[n] = ip.addr[n];
		n = iblocks(ip.addr[ND], 1, list, n, want);
		n = iblocks(ip.addr[ND + 1], 2, list, n, want);
		n = iblocks(ip.addr[ND + 2], 3, list, n, want);
		for (o = 0; o < n; o++)
			printf("%lu\n", list[o]);
		free(list);
		return;
	}
	if ((ip.mode & IFMT) != IFDIR) {
		lsline(&ip, path);
		return;
	}
	d = iread(&ip, &len);
	for (o = 0; o + DIRENT <= len; o += DIRENT) {
		if ((ino = (long)get16(d, o)) == 0)
			continue;
		memcpy(name, d + o + 2, DIRSIZ);
		name[DIRSIZ] = 0;
		iget(ino, &ce);
		lsline(&ce, name);
	}
	free(d);
}

static void
cmdread(cmd, bases, nbases, path)
char *cmd;
long *bases, nbases;
char *path;
{
	char *why;
	long i;

	why = "no such file or directory";
	for (i = 0; i < nbases; i++) {
		base = bases[i];
		if (namei(path, &why) != 0) {
			doread(cmd, path);
			return;
		}
	}
	die("%s: %s", path, why);
}

/* ---- put -------------------------------------------------------------- */

/* Pop a block off the free stack, zero it, and return it. */
static long
balloc_free(fs)
struct fs *fs;
{
	unsigned char sb[BS], nb[BS];
	unsigned long nfree, bno;

	rblk(1L, sb);
	if ((nfree = get16(sb, S_NFREE)) == 0)
		die("free list exhausted");
	nfree--;
	bno = get32(sb, S_FREE + 4 * nfree);
	if (nfree == 0) {
		/*
		 * s_free[0] names the block holding the next link: df_nfree at
		 * 0, df_free[64] at 2.  The whole link is copied, since a short
		 * copy leaves entries that are popped twice.
		 */
		if (bno == 0)
			die("out of disk space");
		rblk((long)bno, nb);
		nfree = get16(nb, 0);
		memcpy(sb + S_FREE, nb + 2, 4 * NICFREE);
	}
	put16(sb, S_NFREE, nfree);
	wblk(1L, sb);
	if (bno == 0 || bno >= (unsigned long)fs->fsize)
		die("bad free block %lu", bno);
	memset(nb, 0, BS);
	wblk((long)bno, nb);
	return (long)bno;
}

/* A free inode, from the superblock's cache or by scanning the table. */
static long
ialloc_free(fs)
struct fs *fs;
{
	unsigned char sb[BS];
	struct ino ip;
	unsigned long n, t;
	long ino, i;

	rblk(1L, sb);
	if ((n = get16(sb, S_NINODE)) != 0) {
		n--;
		ino = (long)get16(sb, S_INODE + 2 * n);
		put16(sb, S_NINODE, n);
	} else {
		ino = 0;
		for (i = 1; i <= (fs->isize - 2) * 8; i++) {
			iget(i, &ip);
			if (ip.mode == 0) {
				ino = i;
				break;
			}
		}
		if (ino == 0)
			die("no free inode in the partition");
	}
	if ((t = get16(sb, S_TINODE)) != 0)
		put16(sb, S_TINODE, t - 1);
	wblk(1L, sb);
	return ino;
}

/* Read-modify-write one inode's 64 bytes. */
static void
iupdate(ino, f, arg)
long ino;
void (*f)();
unsigned long *arg;
{
	unsigned char b[BS];

	rblk(inoblk(ino), b);
	(*f)(b + inooff(ino), arg);
	wblk(inoblk(ino), b);
}

/* Append an entry to a directory, a block at a time, direct blocks only. */
static void
dirlink(fs, dino, name, ino)
struct fs *fs;
long dino;
char *name;
long ino;
{
	unsigned char b[BS], e[BS];
	unsigned long size, blk;
	long slot, off;

	if (strlen(name) > DIRSIZ)
		die("%s: name is longer than %d bytes", name, DIRSIZ);
	rblk(inoblk(dino), b);
	size = get32(b, inooff(dino) + DI_SIZE);
	slot = (long)(size / BS);
	off = (long)(size % BS);
	if (off == 0) {
		if (slot >= ND)
			die("%s: directory needs an indirect block", name);
		blk = (unsigned long)balloc_free(fs);
		rblk(inoblk(dino), b);
		putl3(b, inooff(dino) + DI_ADDR + 3 * slot, blk);
	} else
		blk = getl3(b, inooff(dino) + DI_ADDR + 3 * slot);
	put32(b, inooff(dino) + DI_SIZE, size + DIRENT);
	wblk(inoblk(dino), b);
	rblk((long)blk, e);
	memset(e + off, 0, DIRENT);
	put16(e, off, (unsigned long)ino);
	memcpy(e + off + 2, name, strlen(name));
	wblk((long)blk, e);
}

/* Write data into newly allocated blocks and return the 13 addresses. */
static void
putdata(fs, data, len, addr)
struct fs *fs;
unsigned char *data;
long len;
unsigned long *addr;
{
	unsigned char b[BS], ib[BS], db[BS];
	unsigned long *blocks;
	long nblk, i, j, k, l1, take;

	nblk = (len + BS - 1) / BS;
	if (nblk > ND + NBN + (long)NBN * NBN)
		die("file too large (%ld blocks)", nblk);
	blocks = xalloc((size_t)(nblk + 1) * sizeof(*blocks));
	for (i = 0; i < nblk; i++) {
		blocks[i] = (unsigned long)balloc_free(fs);
		memset(b, 0, BS);
		take = len - i * BS < BS ? len - i * BS : BS;
		memcpy(b, data + i * BS, (size_t)take);
		wblk((long)blocks[i], b);
	}
	for (i = 0; i < NADDR; i++)
		addr[i] = i < ND && i < nblk ? blocks[i] : 0;
	i = ND;
	if (i < nblk) {
		addr[ND] = (unsigned long)balloc_free(fs);
		memset(ib, 0, BS);
		for (k = 0; k < NBN && i < nblk; k++, i++)
			put32(ib, 4 * k, blocks[i]);
		wblk((long)addr[ND], ib);
	}
	if (i < nblk) {
		addr[ND + 1] = (unsigned long)balloc_free(fs);
		memset(db, 0, BS);
		for (j = 0; i < nblk; j++) {
			l1 = balloc_free(fs);
			put32(db, 4 * j, (unsigned long)l1);
			memset(ib, 0, BS);
			for (k = 0; k < NBN && i < nblk; k++, i++)
				put32(ib, 4 * k, blocks[i]);
			wblk(l1, ib);
		}
		wblk((long)addr[ND + 1], db);
	}
	free(blocks);
}

static void
ichmod(e, arg)
unsigned char *e;
unsigned long *arg;
{
	e[DI_MODE] = arg[0] & 0xFF;
	e[DI_MODE + 1] = (e[DI_MODE + 1] & 0xF0) | ((arg[0] >> 8) & 0x0F);
}

static void
inew(e, arg)
unsigned char *e;
unsigned long *arg;
{
	memset(e, 0, INOSZ);
	put16(e, DI_MODE, IFREG | (arg[0] & 07777));
	put16(e, DI_NLINK, 1L);
}

static void
iaddrs(e, arg)
unsigned char *e;
unsigned long *arg;
{
	int i;

	for (i = 0; i < NADDR; i++)
		putl3(e, DI_ADDR + 3 * i, arg[i]);
	put32(e, DI_SIZE, arg[NADDR]);
}

static unsigned char *
slurp(name, lenp)
char *name;
long *lenp;
{
	FILE *f;
	unsigned char *d;
	long cap, n;
	size_t got;

	if ((f = fopen(name, "rb")) == 0)
		die("%s: %s", name, strerror(errno));
	cap = 65536;
	d = xalloc((size_t)cap);
	n = 0;
	while ((got = fread(d + n, 1, (size_t)(cap - n), f)) > 0) {
		n += (long)got;
		if (n == cap)
			d = xgrow(d, (size_t)(cap *= 2));
	}
	if (ferror(f))
		die("%s: read error", name);
	fclose(f);
	*lenp = n;
	return d;
}

static void
cmdput(fs, host, path, havemode, mode)
struct fs *fs;
char *host, *path;
int havemode;
unsigned long mode;
{
	unsigned char *data;
	unsigned long arg[NADDR + 1], m;
	struct ino ip;
	char *why, *dir, *name;
	long len, ino, dino, old;

	data = slurp(host, &len);
	if ((ino = namei(path, &why)) == 0) {
		dir = xstrdup(path);
		while (*dir && dir[strlen(dir) - 1] == '/')
			dir[strlen(dir) - 1] = 0;
		if ((name = strrchr(dir, '/')) != 0)
			*name++ = 0;
		else {
			name = dir;
			dir = "";
		}
		if ((dino = namei(dir, &why)) == 0)
			die("%s: %s", dir, why);
		ino = ialloc_free(fs);
		m = havemode ? mode : 0644;
		iupdate(ino, inew, &m);
		dirlink(fs, dino, name, ino);
	} else if (havemode)
		iupdate(ino, ichmod, &mode);
	iget(ino, &ip);
	old = (long)ip.size;
	putdata(fs, data, len, arg);
	arg[NADDR] = (unsigned long)len;
	iupdate(ino, iaddrs, arg);
	printf("  %s: inode %ld, %ld -> %ld bytes (%ld blocks)\n",
	       path, ino, old, len, (len + BS - 1) / BS);
	free(data);
}

/* ---- mkfs ------------------------------------------------------------- */

static struct fs mk;
static long nextino, nextblk;

/* One manifest line: the path and its fields, in file order. */
struct ment {
	char *path;
	char *f[6];
	int nf;
};

struct manifest {
	struct ment *e;
	long n;
};

static struct manifest perms, devs;

/* Hard links seen so far in this filesystem: host identity -> inode. */
struct hlink {
	unsigned long vol, hi, lo;
	long num;
};
static struct hlink *links;
static long nlinks, caplinks;

static void
readmanifest(dir, name, m, nf1, nf2)
char *dir, *name;
struct manifest *m;
int nf1, nf2;
{
	char path[4096], line[4096], *p, *f[8];
	FILE *fp;
	long i;
	int n;

	m->e = 0;
	m->n = 0;
	sprintf(path, "%.4000s/%s", dir, name);
	if ((fp = fopen(path, "r")) == 0)
		return;
	while (fgets(line, sizeof line, fp) != 0) {
		if ((p = strchr(line, '#')) != 0)
			*p = 0;
		n = 0;
		for (p = strtok(line, " \t\r\n\f\v"); p != 0;
		     p = strtok(0, " \t\r\n\f\v")) {
			if (n == 8)
				break;
			f[n++] = p;
		}
		if (n == 0)
			continue;
		if (n != nf1 && n != nf2)
			die("bad %s line: %s", name, f[0]);
		/* A path named twice keeps its place and takes the later fields. */
		for (i = 0; i < m->n; i++)
			if (strcmp(m->e[i].path, f[0]) == 0)
				break;
		if (i == m->n) {
			m->e = xgrow(m->e, (size_t)(m->n + 1) * sizeof(*m->e));
			m->e[i].path = xstrdup(f[0]);
			m->n++;
		}
		m->e[i].nf = n - 1;
		for (n = 1; n <= m->e[i].nf; n++)
			m->e[i].f[n - 1] = xstrdup(f[n]);
	}
	fclose(fp);
}

static unsigned long
octal(s, what)
char *s, *what;
{
	char *e;
	unsigned long v;

	v = strtoul(s, &e, 8);
	if (*s == 0 || *e != 0)
		die("%s: bad octal number %s", what, s);
	return v;
}

static unsigned long
decimal(s, what)
char *s, *what;
{
	char *e;
	unsigned long v;

	v = strtoul(s, &e, 10);
	if (*s == 0 || *e != 0)
		die("%s: bad number %s", what, s);
	return v;
}

static void
permfor(rel, dflt, ftype, mode, uid, gid)
char *rel;
unsigned long dflt, ftype, *mode, *uid, *gid;
{
	long i;

	for (i = 0; i < perms.n; i++)
		if (strcmp(perms.e[i].path, rel) == 0) {
			*mode = octal(perms.e[i].f[0], rel) | ftype;
			*uid = decimal(perms.e[i].f[1], rel);
			*gid = decimal(perms.e[i].f[2], rel);
			return;
		}
	*mode = dflt | ftype;
	*uid = 0;
	*gid = 1;
}

/* Blocks a file of n bytes occupies, indirect blocks included. */
static long
fileblocks(n)
long n;
{
	long nblk, t;

	nblk = (n + BS - 1) / BS;
	t = nblk;
	if (nblk > ND)
		t++;
	if (nblk > ND + NBN)
		t += 1 + (nblk - (ND + NBN) + NBN - 1) / NBN;
	return t;
}

static long
mkballoc()
{
	if (nextblk >= mk.fsize)
		die("filesystem full at block %ld", nextblk);
	return nextblk++;
}

static long
mkialloc()
{
	if (nextino > (mk.isize - 2) * 8)
		die("out of inodes");
	return nextino++;
}

static void
mkwblk(n, b)
long n;
unsigned char *b;
{
	if (n < mk.isize || n >= mk.fsize)
		die("block %ld outside data area", n);
	wblk(n, b);
}

/* Store a file's data in the next free blocks, as putdata does, but taking
 * them in order off the allocation cursor rather than from a free list. */
static void
mkdata(data, len, addr)
unsigned char *data;
long len;
unsigned long *addr;
{
	unsigned char b[BS], ib[BS], db[BS];
	unsigned long *blocks;
	long nblk, i, j, k, l1, take, start;

	start = nextblk;
	nblk = (len + BS - 1) / BS;
	blocks = xalloc((size_t)(nblk + 1) * sizeof(*blocks));
	for (i = 0; i < nblk; i++) {
		blocks[i] = (unsigned long)mkballoc();
		memset(b, 0, BS);
		take = len - i * BS < BS ? len - i * BS : BS;
		memcpy(b, data + i * BS, (size_t)take);
		mkwblk((long)blocks[i], b);
	}
	for (i = 0; i < NADDR; i++)
		addr[i] = i < ND && i < nblk ? blocks[i] : 0;
	i = ND;
	if (i < nblk) {
		addr[ND] = (unsigned long)mkballoc();
		memset(ib, 0, BS);
		for (k = 0; k < NBN && i < nblk; k++, i++)
			put32(ib, 4 * k, blocks[i]);
		mkwblk((long)addr[ND], ib);
	}
	if (i < nblk) {
		addr[ND + 1] = (unsigned long)mkballoc();
		memset(db, 0, BS);
		for (j = 0; i < nblk; j++) {
			if (j >= NBN)
				die("file too large (triple indirect)");
			l1 = mkballoc();
			put32(db, 4 * j, (unsigned long)l1);
			memset(ib, 0, BS);
			for (k = 0; k < NBN && i < nblk; k++, i++)
				put32(ib, 4 * k, blocks[i]);
			mkwblk(l1, ib);
		}
		mkwblk((long)addr[ND + 1], db);
	}
	free(blocks);
	if (nextblk - start != fileblocks(len))
		die("allocated %ld blocks for %ld bytes, expected %ld",
		    nextblk - start, len, fileblocks(len));
}

static void
mkinode(ino, mode, nlink, uid, gid, size, addr, rdev)
long ino;
unsigned long mode, nlink, uid, gid, size, *addr;
long rdev;
{
	unsigned char b[BS], *e;
	int i;

	rblk(inoblk(ino), b);
	e = b + inooff(ino);
	memset(e, 0, INOSZ);
	put16(e, DI_MODE, mode);
	put16(e, DI_NLINK, nlink);
	put16(e, DI_UID, uid);
	put16(e, DI_GID, gid);
	put32(e, DI_SIZE, size);
	for (i = 0; i < NADDR; i++)
		putl3(e, DI_ADDR + 3 * i, addr ? addr[i] : 0);
	if (rdev >= 0)
		put16(e, DI_ADDR, (unsigned long)rdev);
	put32(e, DI_ATIME, (unsigned long)STAMP);
	put32(e, DI_MTIME, (unsigned long)STAMP);
	put32(e, DI_CTIME, (unsigned long)STAMP);
	wblk(inoblk(ino), b);
}

static void
bumplink(ino)
long ino;
{
	unsigned char b[BS];

	rblk(inoblk(ino), b);
	put16(b, inooff(ino) + DI_NLINK, get16(b, inooff(ino) + DI_NLINK) + 1);
	wblk(inoblk(ino), b);
}

struct dent {
	char *name;
	long ino;
};

struct sub {
	char *full, *rel;
	long ino;
};

static int
namecmp(a, b)
const void *a, *b;
{
	return strcmp(*(char **)a, *(char **)b);
}

static char *
join(a, b)
char *a, *b;
{
	char *p;

	if (*a == 0)
		return xstrdup(b);
	p = xalloc(strlen(a) + strlen(b) + 2);
	sprintf(p, "%s/%s", a, b);
	return p;
}

/*
 * The directory part of a manifest path, as os.path.split gives it: all of it
 * before the last slash, with trailing slashes dropped unless that is all
 * there is.  So `dev/hd0' is in `dev', `hd0' is at the root, and `/hd0' is
 * in `/', which is no directory of a staging tree.
 */
static char *
dirpart(path, namep)
char *path, **namep;
{
	char *d, *s;
	size_t n, k;

	d = xstrdup(path);
	if ((s = strrchr(d, '/')) == 0) {
		*namep = path;
		*d = 0;
		return d;
	}
	*namep = path + (s - d) + 1;
	n = s - d + 1;
	d[n] = 0;
	for (k = 0; k < n && d[k] == '/'; k++)
		;
	if (k < n)
		while (n > 0 && d[n - 1] == '/')
			d[--n] = 0;
	return d;
}

/*
 * Which host file a staged regular file is, and how many names it has.  The
 * identity is (vol, hi, lo): st_dev and st_ino on POSIX, the volume serial
 * and file index on Windows.
 */
static unsigned long
fileid(path, st, vol, hi, lo)
char *path;
struct stat *st;
unsigned long *vol, *hi, *lo;
{
#ifdef _WIN32
	BY_HANDLE_FILE_INFORMATION fi;
	HANDLE h;

	h = CreateFileA(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE
			| FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
	if (h == INVALID_HANDLE_VALUE || !GetFileInformationByHandle(h, &fi))
		die("%s: cannot read its file identity", path);
	CloseHandle(h);
	*vol = fi.dwVolumeSerialNumber;
	*hi = fi.nFileIndexHigh;
	*lo = fi.nFileIndexLow;
	return fi.nNumberOfLinks;
#else
	*vol = (unsigned long)st->st_dev;
	*hi = 0;
	*lo = (unsigned long)st->st_ino;
	return (unsigned long)st->st_nlink;
#endif
}

static void
adddir(path, rel, ino, parent)
char *path, *rel;
long ino, parent;
{
	DIR *dp;
	struct dirent *de;
	struct stat st;
	char **names, *full, *r, *dd, *dname, *t;
	struct dent *ents;
	struct sub *subs;
	unsigned char *data;
	unsigned long addr[NADDR], mode, uid, gid, nlink, vol, hi, lo;
	long nnames, cap, nents, nsubs, i, j, len, cino, maj, mnr;

	if ((dp = opendir(path)) == 0)
		die("%s: %s", path, strerror(errno));
	names = 0;
	nnames = cap = 0;
	while ((de = readdir(dp)) != 0) {
		if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
			continue;
		if (*rel == 0 && (strcmp(de->d_name, "DEVICES") == 0
		 || strcmp(de->d_name, "MANIFEST") == 0))
			continue;
		if (nnames == cap)
			names = xgrow(names, (size_t)(cap = cap ? 2 * cap : 64)
				      * sizeof(*names));
		names[nnames++] = xstrdup(de->d_name);
	}
	closedir(dp);
	qsort(names, (size_t)nnames, sizeof(*names), namecmp);

	ents = xalloc((size_t)(nnames + devs.n + 1) * sizeof(*ents));
	subs = xalloc((size_t)(nnames + 1) * sizeof(*subs));
	nents = nsubs = 0;
	for (i = 0; i < nnames; i++) {
		full = join(path, names[i]);
		r = join(rel, names[i]);
		if (lstat(full, &st) < 0)
			die("%s: %s", full, strerror(errno));
		if (S_ISDIR(st.st_mode)) {
			cino = mkialloc();
			ents[nents].name = names[i];
			ents[nents++].ino = cino;
			subs[nsubs].full = full;
			subs[nsubs].rel = r;
			subs[nsubs++].ino = cino;
			continue;
		}
		if (!S_ISREG(st.st_mode))
			die("unsupported file type: %s", full);
		nlink = fileid(full, &st, &vol, &hi, &lo);
		if (nlink > 1) {
			for (j = 0; j < nlinks; j++)
				if (links[j].vol == vol && links[j].hi == hi
				 && links[j].lo == lo)
					break;
			if (j < nlinks) {
				bumplink(links[j].num);
				ents[nents].name = names[i];
				ents[nents++].ino = links[j].num;
				free(full);
				free(r);
				continue;
			}
		}
		cino = mkialloc();
		if (nlink > 1) {
			if (nlinks == caplinks)
				links = xgrow(links, (size_t)(caplinks = caplinks
					      ? 2 * caplinks : 64) * sizeof(*links));
			links[nlinks].vol = vol;
			links[nlinks].hi = hi;
			links[nlinks].lo = lo;
			links[nlinks++].num = cino;
		}
		data = slurp(full, &len);
		mkdata(data, len, addr);
		free(data);
		permfor(r, (st.st_mode & 0111) ? 0755UL : 0644UL, (unsigned long)IFREG,
			&mode, &uid, &gid);
		mkinode(cino, mode, 1UL, uid, gid, (unsigned long)len, addr, -1L);
		ents[nents].name = names[i];
		ents[nents++].ino = cino;
		free(full);
		free(r);
	}

	/* Device nodes at this level, in DEVICES order. */
	for (i = 0; i < devs.n; i++) {
		dd = dirpart(devs.e[i].path, &dname);
		if (strcmp(dd, rel) == 0) {
			t = devs.e[i].f[0];
			maj = (long)decimal(devs.e[i].f[2], devs.e[i].path);
			mnr = (long)decimal(devs.e[i].f[3], devs.e[i].path);
			if (devs.e[i].nf == 6) {
				uid = decimal(devs.e[i].f[4], devs.e[i].path);
				gid = decimal(devs.e[i].f[5], devs.e[i].path);
			} else {
				uid = 0;
				gid = 1;
			}
			cino = mkialloc();
			mode = octal(devs.e[i].f[1], devs.e[i].path)
			     | (strcmp(t, "b") == 0 ? IFBLK : IFCHR);
			mkinode(cino, mode, 1UL, uid, gid, 0UL, (unsigned long *)0,
				(mnr | (maj << 8)) & 0xFFFF);
			ents[nents].name = dname;
			ents[nents++].ino = cino;
		}
		free(dd);
	}

	/* The directory's own data: `.', `..', then the entries. */
	len = (nents + 2) * DIRENT;
	data = xalloc((size_t)len);
	put16(data, 0L, (unsigned long)ino);
	data[2] = '.';
	put16(data, (long)DIRENT, (unsigned long)parent);
	data[DIRENT + 2] = data[DIRENT + 3] = '.';
	for (i = 0; i < nents; i++) {
		put16(data, (i + 2) * DIRENT, (unsigned long)ents[i].ino);
		j = (long)strlen(ents[i].name);
		memcpy(data + (i + 2) * DIRENT + 2, ents[i].name,
		       (size_t)(j < DIRSIZ ? j : DIRSIZ));
	}
	mkdata(data, len, addr);
	free(data);
	/*
	 * A directory's link count is one per name for it: its own `.', the
	 * `..' of each subdirectory, and its entry in its parent -- 2 + nsubs.
	 * The root has no entry in a parent, and dcheck counts the missing one
	 * anyway, so the root is 3 + nsubs.
	 */
	permfor(rel, 0755UL, (unsigned long)IFDIR, &mode, &uid, &gid);
	mkinode(ino, mode, (unsigned long)((ino == ROOTIN ? 3 : 2) + nsubs),
		uid, gid, (unsigned long)len, addr, -1L);
	free(ents);
	for (i = 0; i < nsubs; i++) {
		adddir(subs[i].full, subs[i].rel, subs[i].ino, ino);
		free(subs[i].full);
		free(subs[i].rel);
	}
	free(subs);
	for (i = 0; i < nnames; i++)
		free(names[i]);
	free(names);
}

/*
 * The V7 free chain, built by replaying the kernel's bfree() over every unused
 * data block, highest first, so allocation later pops them lowest first.  A
 * link is spilled into the block being freed whenever the stack is empty or
 * full, so the first block freed receives an all-zero link -- df_nfree 0 --
 * which is where the kernel's balloc() and icheck stop.  Seeding the stack
 * with a 0 entry instead puts a phantom block 0 in the chain.
 */
static void
mksuper()
{
	unsigned char b[BS];
	unsigned long free_[NICFREE], nfree, tfree, ninodes, nused, n;
	long blk;
	int i;

	nfree = tfree = 0;
	memset(free_, 0, sizeof free_);
	for (blk = mk.fsize - 1; blk >= nextblk; blk--) {
		if (nfree == 0 || nfree == NICFREE) {
			memset(b, 0, BS);
			put16(b, 0L, nfree);
			for (i = 0; i < NICFREE; i++)
				put32(b, 2 + 4 * i, free_[i]);
			mkwblk(blk, b);
			nfree = 0;
			memset(free_, 0, sizeof free_);
		}
		free_[nfree++] = (unsigned long)blk;
		tfree++;
	}
	ninodes = (unsigned long)(mk.isize - 2) * 8;
	nused = (unsigned long)(nextino - 1);
	memset(b, 0, BS);
	put16(b, (long)S_ISIZE, (unsigned long)mk.isize);
	put32(b, (long)S_FSIZE, (unsigned long)mk.fsize);
	put16(b, (long)S_NFREE, nfree);
	for (i = 0; i < NICFREE; i++)
		put32(b, S_FREE + 4 * i, free_[i]);
	/* Every inode below the cursor is in use, every one above it free. */
	n = 0;
	while (n < NICINOD && nused + 1 + n <= ninodes) {
		put16(b, S_INODE + 2 * n, nused + 1 + n);
		n++;
	}
	put16(b, (long)S_NINODE, n);
	/* s_dirty stays 0, clean: a new image has never been mounted. */
	put32(b, (long)S_TIME, (unsigned long)STAMP);
	put32(b, (long)S_TFREE, tfree);
	put16(b, (long)S_TINODE, ninodes - nused);
	put16(b, (long)S_M, 1UL);
	put16(b, (long)S_N, 1UL);
	memcpy(b + S_FNAME, "nonamenopack", 12);
	wblk(1L, b);
	printf("fs@%-6ld %5ld/%ld blocks used, %lu/%lu inodes used\n",
	       base, nextblk, mk.fsize, nused, ninodes);
}

static void
cmdmkfs(fsize, isize, stage)
long fsize, isize;
char *stage;
{
	unsigned char z[BS];
	struct stat st;
	long i;

	if (isize < 3 || fsize <= isize)
		die("fsize %ld and isize %ld make no filesystem", fsize, isize);
	if (stat(stage, &st) < 0 || !S_ISDIR(st.st_mode))
		die("%s: not a directory", stage);
	mk.fsize = fsize;
	mk.isize = isize;
	nextino = ROOTIN + 1;
	nextblk = isize;
	memset(z, 0, BS);
	for (i = 0; i < fsize; i++)
		wblk(i, z);
	/* The bad-block file: allocated, empty, no links, as mkfs makes it. */
	mkinode((long)BADFIN, (unsigned long)IFREG, 0UL, 0UL, 0UL, 0UL,
		(unsigned long *)0, -1L);
	readmanifest(stage, "DEVICES", &devs, 5, 7);
	readmanifest(stage, "MANIFEST", &perms, 4, 4);
	adddir(stage, "", (long)ROOTIN, (long)ROOTIN);
	mksuper();
}

/* ---- main ------------------------------------------------------------- */

static void
usage()
{
	fprintf(stderr, "usage:\tcohfs mkfs -p BLK IMAGE FSIZE ISIZE STAGEDIR\n"
		"\tcohfs ls|cat|find|blocks [-p BLK] IMAGE PATH\n"
		"\tcohfs put -p BLK [-m MODE] IMAGE HOSTFILE GUESTPATH...\n"
		"\tcohfs parts [-p BLK] IMAGE\n");
	exit(2);
}

static void
readsuper(fs)
struct fs *fs;
{
	unsigned char b[BS];

	rblk(1L, b);
	fs->isize = (long)get16(b, S_ISIZE);
	fs->fsize = (long)get32(b, S_FSIZE);
	if (fs->isize <= 2 || fs->fsize <= fs->isize
	 || get32(b, S_FSIZE) > (unsigned long)(imgblocks - base))
		die("%s: no filesystem at block %ld", imgname, base);
}

int
main(argc, argv)
int argc;
char **argv;
{
	char *cmd;
	long *bases, nbases, i;
	int havep, havem;
	unsigned long mode;
	struct fs fs;

#ifdef _WIN32
	_setmode(_fileno(stdout), _O_BINARY);
#endif
	if (argc < 2)
		usage();
	cmd = argv[1];
	argv += 2;
	argc -= 2;
	havep = havem = 0;
	mode = 0;
	while (argc > 0 && argv[0][0] == '-') {
		if (strcmp(argv[0], "-p") == 0 && argc > 1) {
			base = (long)decimal(argv[1], "-p");
			havep = 1;
		} else if (strcmp(argv[0], "-m") == 0 && argc > 1) {
			mode = octal(argv[1], "-m");
			havem = 1;
		} else
			usage();
		argv += 2;
		argc -= 2;
	}

	if (strcmp(cmd, "mkfs") == 0) {
		if (!havep || havem || argc != 4)
			usage();
		openimg(argv[0], "r+b");
		cmdmkfs((long)decimal(argv[1], "FSIZE"),
			(long)decimal(argv[2], "ISIZE"), argv[3]);
		closeimg();
	} else if (strcmp(cmd, "ls") == 0 || strcmp(cmd, "cat") == 0
		|| strcmp(cmd, "find") == 0 || strcmp(cmd, "blocks") == 0) {
		if (havem || argc != 2)
			usage();
		openimg(argv[0], "rb");
		if (havep) {
			bases = &base;
			nbases = 1;
		} else {
			nbases = parts((long *)0);
			bases = xalloc((size_t)(nbases + 1) * sizeof(*bases));
			parts(bases);
			if (nbases == 0)
				die("no COHERENT filesystem found in %s", imgname);
		}
		cmdread(cmd, bases, nbases, argv[1]);
		fclose(img);
	} else if (strcmp(cmd, "put") == 0) {
		if (!havep || argc < 3 || (argc - 1) % 2 != 0)
			usage();
		openimg(argv[0], "r+b");
		readsuper(&fs);
		for (i = 1; i < argc; i += 2)
			cmdput(&fs, argv[i], argv[i + 1], havem, mode);
		closeimg();
		printf("written: %s\n", imgname);
	} else if (strcmp(cmd, "parts") == 0) {
		if (havem || argc != 1)
			usage();
		openimg(argv[0], "rb");
		if (havep) {
			if (!isfs())
				die("%s: no filesystem at block %ld", imgname, base);
			bases = xalloc(sizeof(*bases));
			bases[0] = base;
			nbases = 1;
		} else {
			nbases = parts((long *)0);
			bases = xalloc((size_t)(nbases + 1) * sizeof(*bases));
			parts(bases);
		}
		for (i = 0; i < nbases; i++) {
			unsigned char b[BS];

			base = bases[i];
			rblk(1L, b);
			printf("%ld %lu %lu %lu %lu\n", base, get32(b, S_FSIZE),
			       get16(b, S_ISIZE), get32(b, S_TFREE),
			       get16(b, S_TINODE));
		}
		fclose(img);
	} else
		usage();
	return 0;
}
