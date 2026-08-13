/*
 * netinet/in.h -- Internet address family for the COHERENT/Z8001 socket API.
 * Compact K&R header over the Minix inet stack (see os/net).
 */
#ifndef NETINET_IN_H
#define NETINET_IN_H

#include <sys/types.h>

typedef unsigned long	in_addr_t;	/* 32-bit IPv4 address		*/
typedef unsigned short	in_port_t;	/* 16-bit port			*/

struct in_addr {
	in_addr_t	s_addr;		/* address in network byte order */
};

/* Protocol families / address families. */
#define AF_UNSPEC	0
#define AF_INET		2
#define PF_INET		AF_INET

#define INADDR_ANY		((in_addr_t)0x00000000L)
#define INADDR_BROADCAST	((in_addr_t)0xffffffffL)
#define INADDR_LOOPBACK		((in_addr_t)0x7f000001L)

/* IP protocols. */
#define IPPROTO_IP	0
#define IPPROTO_ICMP	1
#define IPPROTO_TCP	6
#define IPPROTO_UDP	17

struct sockaddr_in {
	short		sin_family;	/* AF_INET			*/
	in_port_t	sin_port;	/* port, network byte order	*/
	struct in_addr	sin_addr;	/* address			*/
	char		sin_zero[8];	/* pad to sizeof(sockaddr)	*/
};

/*
 * The Z8001 is big-endian = network byte order, so these are identities
 * (matching net/hton.h's BIG_ENDIAN path).
 */
#define htons(x)	(x)
#define ntohs(x)	(x)
#define htonl(x)	(x)
#define ntohl(x)	(x)

/*
 * inet_addr returns INADDR_NONE (0xFFFFFFFF) for anything that is not four
 * dotted decimal numbers -- which is also the value of 255.255.255.255, the
 * historical BSD ambiguity.  inet_aton() reports failure separately and is the
 * one to use where the broadcast address has to be told from an error.
 */
#define INADDR_NONE	0xFFFFFFFFL
in_addr_t inet_addr();		/* "a.b.c.d" -> in_addr_t (net order)	*/
int inet_aton();		/* (char *, struct in_addr *) -> 1/0	*/
char	 *inet_ntoa();		/* struct in_addr -> "a.b.c.d"		*/

#endif /* NETINET_IN_H */
