#include <stdlib.h>

int main(int argc, char **argv)
{
	int i = 0;
	int len = atoi(argv[argc - 1]);

	while (i <= len)
		i++;
	return i;
}