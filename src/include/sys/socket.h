/*
 * sys/socket.h -- BSD socket API for COHERENT/Z8001.
 *
 * A thin veneer (libsocket, see os/net/libsocket.c) over the Minix inet stack's
 * device+ioctl interface, reached through the inet daemon's control channel.
 */
#ifndef SYS_SOCKET_H
#define SYS_SOCKET_H

#include <sys/types.h>

typedef unsigned int	socklen_t;

/* Socket types. */
#define SOCK_STREAM	1		/* TCP				*/
#define SOCK_DGRAM	2		/* UDP				*/
#define SOCK_RAW	3		/* raw IP			*/

/* Address families (see <netinet/in.h> for AF_INET). */
#define AF_UNSPEC	0
#define AF_INET		2

/* shutdown() how. */
#define SHUT_RD		0
#define SHUT_WR		1
#define SHUT_RDWR	2

/*
 * setsockopt levels and options, at their BSD values.
 *
 * This stack has no per-option control -- a socket's behaviour is fixed by the
 * flag word given to the stack when it was bound -- so libsocket succeeds only
 * for the options that flag word already grants and answers ENOPROTOOPT for
 * the rest.  See setsockopt() there.
 */
#define SOL_SOCKET	0xffff
#define SO_REUSEADDR	0x0004
#define SO_KEEPALIVE	0x0008
#define SO_BROADCAST	0x0020
#define SO_USELOOPBACK	0x0040
#define SO_ERROR	0x1007
#define SO_TYPE		0x1008

struct sockaddr {
	short	sa_family;		/* address family		*/
	char	sa_data[14];		/* address (protocol-specific)	*/
};

int	socket();
int	bind();
int	connect();
int	listen();
int	accept();
int	send();
int	recv();
int	sendto();
int	recvfrom();
int	shutdown();
int	setsockopt();
int	getsockopt();
int	getsockname();
int	getpeername();

#endif /* SYS_SOCKET_H */
