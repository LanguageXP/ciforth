/* Copyright (2000): Albert van der Horst, HCC FIG Holland by GNU Public License */
#include <stdio.h>
#include <stdlib.h>
#include <sys/times.h>
#include <unistd.h>
#include <string.h>
#include <sys/time.h>
#include <termios.h> 
 
/* The maximum size of a Forth command passed to the OS */
#define MAX_COMMAND 2000

/* public declarations */ 
struct ttystate { struct termios tio; }; 
struct tty      { int fd; struct ttystate org; struct ttystate now; };  
 
extern int errno;
int nodevice;

/* ****************************************************************************
 * tty_error(),tty_warning():
 *     error handling and cleanup
 * ***************************************************************************/
void 
tty_error (char *s)
{
  fprintf (stderr, "\n\nerror: %s, (%s)\n", s, sys_errlist[errno]);
  fflush (stderr);
}

void 
tty_warning (char *s)
{
  fprintf (stderr, "\n\nwarning: %s, (%s)\n", s, sys_errlist[errno]);
  fflush (stderr);
}

/* ****************************************************************************
 * tty_init(), tty_set(), tty_restore()  : 
 *     primitive functions to encapsulate terminal state changes. Any
 *     terminal state modification is done through this two functions.
 * ***************************************************************************/
void 
tty_set (struct tty *ptty)
{
  if (nodevice)
    return;
  if (tcsetattr (ptty->fd, TCSADRAIN, &ptty->now.tio) < 0)
    tty_error ("unable to set tty state");
}

void 
tty_restore (struct tty *ptty)
{				/* write termio struct */
  if (nodevice)
    return;
  if (tcsetattr (ptty->fd, TCSADRAIN, &ptty->org.tio) < 0)
    tty_error ("unable to restore tty state");
}

void 
tty_init (int fd, struct tty *ptty)
{				/* fill-in tty struct */
  ptty->fd = fd;
  nodevice = 0;
  /* save original tty_state */
  if (tcgetattr (ptty->fd, &ptty->org.tio) < 0)
    nodevice = 1;
  if (nodevice)
    return;
  /* template for new tty_state */
  if (tcgetattr (ptty->fd, &ptty->now.tio) < 0)
    nodevice = 1;
  if (nodevice)
    return;
  /* disable some special characters */
  ptty->now.tio.c_cc[VINTR] = _POSIX_VDISABLE;
  ptty->now.tio.c_cc[VQUIT] = _POSIX_VDISABLE;
  ptty->now.tio.c_cc[VSUSP] = _POSIX_VDISABLE;
  tty_set (ptty);
}

/* ****************************************************************************
 * tty_echo(), tty_noecho() :
 *     change tty attributes
 * ***************************************************************************/
void 
tty_echo (struct tty *ptty)
{
  if (nodevice)
    return;
  ptty->now.tio.c_lflag |= ECHO;
  tty_set (ptty);
}

void 
tty_noecho (struct tty *ptty)
{
  if (nodevice)
    return;
  ptty->now.tio.c_lflag &= ~ECHO;
  tty_set (ptty);
}

/* ****************************************************************************
 * tty_keymode(), tty_linemode() :
 *    change main tty operating mode
 * ***************************************************************************/
void 
tty_keymode (struct tty *ptty)
{
  if (nodevice)
    return;
  ptty->now.tio.c_lflag &= ~ICANON;
  ptty->now.tio.c_cc[VMIN] = 1;
  ptty->now.tio.c_cc[VTIME] = 0;
  tty_set (ptty);
}

void 
tty_linemode (struct tty *ptty)
{
  if (nodevice)
    return;
  ptty->now.tio.c_lflag |= ICANON;
/* VMIN, VTIME are overloaded and should really be restored ... */
  ptty->now.tio.c_cc[VMIN] = ptty->org.tio.c_cc[VMIN];
  ptty->now.tio.c_cc[VTIME] = ptty->org.tio.c_cc[VTIME];
  tty_set (ptty);
}

/* ************************************************************************** */

int keyq (int fd)
{
  fd_set rfds;
  fd_set afds;
  struct timeval tv;
  int nfds = 1;
  if (nodevice)
    return 1;
  tv.tv_sec = 0;
  tv.tv_usec = 0;
  FD_ZERO (&afds);
  FD_SET (fd, &afds);
  memmove (&rfds, &afds, sizeof (rfds));
  if (select (nfds, &rfds, NULL, NULL, &tv) < 0)	/* any input around? */
    tty_warning ("select failed");
  if (FD_ISSET (fd, &rfds))	/* input from fd? */
    return 1;
  return 0;
}				/* no input */

/*  void (*figforth)() = 0x8050000;                                          */

/* This is absolutely necessary, but I have no clue. */
char reservespace[1000000];

struct tms tm;
struct tty std_in;

int 
qkey (void)
{
  char buf;
  if (nodevice)
    {
      fread (&buf, 1, 1, stdin);
      return buf;
    }
  if (!keyq (0))
    return EOF;
  read (0, &buf, 1);
    return buf;			/* only one */
}

int c_qterm(void)
{
  fd_set rfds;
  struct timeval tv; 

  /* Zero timeout, must be set each time! */
  /* A Linux peculiarity.                 */
  tv.tv_sec = 0;
  tv.tv_usec = 0;

  FD_ZERO(&rfds);
  FD_SET(0, &rfds);    /* From standard input */
  select(1, &rfds, NULL, NULL, &tv); 

  return FD_ISSET(0, &rfds);     
}
 
int c_key( void )
{
  char key;
  int i;
  tty_keymode (&std_in);                                                       
  i=read (0, &key, 1);
  if ( 1!=i) {fprintf(stderr,"oei oei\n"); exit(1);}
  return key;                 
}

void c_emit(int ch)
{
  fputc (ch, stdout);
  fflush (stdout);
}

void c_type(int count, char *buffer)
{
  write (1, buffer, count);
  fflush (stdout);
}

int c_expec(int count, char *buffer)
{
  int i;
  if ( count <= 0 ) return 0;

  tty_linemode (&std_in);                                                       
  i= read(0, buffer, count);
  buffer[--i]=0;  /* Eat the cr. */

  printf(" Har there, we have a total of %d chars\n", i);
  printf(" It looks like **%s**\n", buffer);
  return i;     /* Ignored by fig-Forth, use it and you have ANSI ACCEPT */
}

/* Perform ANSI Forth 'SYSTEM' */
/* Interpret the Forth string (`command',`count') as linux                   */
/* command and execute it.                                                   */
int c_system(int count, char command[])
{
  int i;
  char buffer[MAX_COMMAND];

  if( MAX_COMMAND-1 > count )
      return -1;

  strncpy( buffer, command, count);
  buffer[count]=0;
  buffer[count-1]=0;
  return system (buffer);
}


int main (int argc, char *argv[])
{
  tty_init (0, &std_in);                                                       
  if ( nodevice ) {printf("oei oei nodevice\n");exit(1);}
  figforth (argc, argv);
  tty_restore (&std_in);                                                       
}
