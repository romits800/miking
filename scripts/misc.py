 with open ("a1_32.mi","w") as f:
#usr/bin/python


with open("file.mi") as f:
	f.write("cons (" + " ( cons (".join(["cons " + " (cons ".join(map(str,rlist)) + " nil" + ")"*len(rlist) for rlist in lst]) + " nil" + ")"*(len(lst)-1)
