#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern char *strdup(const char *);

// like sprintf but takes an array of args instead. usage:

//  char *arr[] = {"one", "two", "three"};
//  char str[100];
//  arrprintf(str, "%s, %s, %s", arr);
//  printf("Result: %s\n", str);

int arsprintf(char *str, const char *fmt, char **arr) {
  int cnt = 0, len = 0, bit = 0;
  char *buf, *ptr, *tmp;

  /* fmt must be writable */
  buf = ptr = strdup(fmt);
  if (buf == NULL)
    return -1;

  while ((tmp = ptr)) {
    while ((ptr = strchr(ptr, '%'))) {
      /* Support for %% */
      if (ptr[1] == '%') {
        ptr += 2;
        continue;
      }
      /* Skip first % */
      if (bit ^= 1) {
        ptr += 1;
        continue;
      } else break;
    }

    if (ptr) *ptr = '\0'; /* Tokenize */

    if (strstr(tmp, "%d")) {
      len += sprintf(str + len, tmp, atoi(arr[cnt++]));
    } else {
      len += sprintf(str + len, tmp, arr[cnt++]);
    }

    if (ptr) *ptr = '%'; /* Untokenize */
  }

  free(buf);
  return len;
}