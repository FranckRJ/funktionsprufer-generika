#!/bin/bash

#Desactivation du globbing parce que ca peut poser probleme et que ca sert a rien pour ce script (je suppose).
set -f

dirToCheck="."
dirToCheckIsCustom="false"
execToCheck=""
authors=""
authorizedFuncs=""
checkAuthorFile="true"
checkNorm="true"
checkCodeAuthors="true"
checkMakefile="true"
checkForbidFunc="true"

function print_help
{
read -r -d '' HELP_TEXT << EOM
DESCRIPTION :
Fait divers tests generiques sur un projet.

LISTE DES COMMANDES :
<chemin_vers_projet>          Specifie le chemin vers le projet a tester.
--authors / -a                Specifie la liste des auteurs, avec un ':' comme
                              separateur. La liste ne peut pas contenir d'espaces.
--exec / -e                   Specifie le nom de l'executable du projet.
--funcs / -f                  Specifie la liste des fonctions autorisees.
--noauthorfile                Desactive la verification du fichier auteur.
--nonorm                      Desactive la verification de la norme.
--nocodeauthors               Desactive la verification des auteurs du code.
--nomakefile                  Desactive la verification du Makefile.
--noforbidfunc                Desactive la verification des fonctions interdites.
--help / -h                   Affiche cette page d'aide.
EOM

echo "$HELP_TEXT"
}

function check_author_file
{
	echo -n "Fichier auteur : "
	authorFileContent=""
	if [[ -f "$dirToCheck"/auteur ]]; then
		authorFileContent=$(cat "$dirToCheck"/auteur)
	elif [[ -f "$dirToCheck"/author ]]; then
		authorFileContent=$(cat "$dirToCheck"/author)
	else
		echo "ERREUR : fichier non trouve."
		return
	fi
	if [[ -z $authors ]]; then
		echo "auteurs non initialises."
		return
	fi
	OIFS="$IFS"
	IFS=':
'
	read -a listOfAuthorsInFileContent <<< $authorFileContent
	IFS=':'
	read  -a listOfAuthors <<< $authors
	IFS="$OIFS"
	listOfAuthorsInFileContent=($listOfAuthorsInFileContent)
	listOfAuthors=($listOfAuthors)
	for author in ${listOfAuthorsInFileContent[@]}; do
		if [[ ! " ${listOfAuthors[@]} " =~ " $author " ]]; then
			echo "ERREUR : $author n'est pas dans la liste des auteurs."
			return
		fi
	done
	if [[ ! "${#listOfAuthors[@]}" -eq "${#listOfAuthorsInFileContent[@]}" ]]; then
		echo "ERREUR : tous les auteurs du projet ne sont pas presents dans le fichier auteur."
	else
		echo "OK."
	fi
}

function check_norme
{
	echo -n "Norme : "
	if command -v norminette &> /dev/null; then
		norme_result=$(norminette "$dirToCheck" | grep -v "^Warning: Not a valid file" | grep -v "^Norme: ")
		if [[ -z "$norme_result" ]]; then
			echo "OK."
		else
			echo "ERREUR."
		fi
	else
		echo "norminette non presente."
	fi
}

function check_author_of_code
{
	echo -n "Auteurs du code : "
	if [[ -z $authors ]]; then
		echo "auteurs non initialises."
		return
	fi
	OIFS="$IFS"
	IFS=':'
	read -a listOfAuthors <<< $authors
	IFS="$OIFS"
	findError=$(find "$dirToCheck" \( -name "*.c" -o -name "*.h" \) -print0 |
		while IFS= read -r -d $'\0' codeFile; do
			listOfAuthorsInCodeFileInString=$(head -n 11 "$codeFile" | perl -ne '/(By\:|by) ([^ ]*)/ && print "$2\n"')
			IFS='
'
			read -a listOfAuthorsInCodeFile <<< $listOfAuthorsInCodeFileInString
			IFS=" "
			for authorInCodeFile in ${listOfAuthorsInCodeFile[@]}; do
				if [[ ! " ${listOfAuthors[@]} " =~ " $authorInCodeFile " ]]; then
					echo "ERREUR : l'auteur du fichier $codeFile ($authorInCodeFile) n'est pas un auteur du projet."
					return
				fi
			done
		done)
	if [[ -z "$findError" ]]; then
		echo "OK."
	else
		echo "$findError"
	fi
}

function makefile_check_fclean
{
	make fclean -C "$dirToCheck" &> /dev/null
	if [[ -f "$dirToCheck"/"$execToCheck" ]]; then
		echo "ERREUR : make fclean ne supprime pas l'executable."
		return 1
	fi
	return 0
}

function makefile_check_clean
{
	execWasHere="false"
	if [[ -f "$dirToCheck"/"$execToCheck" ]]; then
		execWasHere="true"
	fi
	make clean -C "$dirToCheck" &> /dev/null
	if [[ "$execWasHere" == "true" ]] && [[ ! -f "$dirToCheck"/"$execToCheck" ]]; then
		echo "ERREUR : make clean a supprime l'executable."
		return 1
	fi
	return 0
}

# Arg $1 == checkItIsNotRecompiled
function makefile_check_make
{
	execTimestamp=$(date -r "$dirToCheck"/"$execToCheck" 2> /dev/null)
	if [[ "$1" == "true" ]]; then
		sleep 2 #pour etre certain que le nouvel executable a un nouveau timestamp s'il relink.
	fi
	make -C "$dirToCheck" &> /dev/null
	if [[ ! -f "$dirToCheck"/"$execToCheck" ]]; then
		echo "ERREUR : make n'a pas cree l'executable."
		return 1
	fi
	if [[ "$1" == "true" ]]; then
		if [[ "$execTimestamp" != $(date -r "$dirToCheck"/"$execToCheck" 2> /dev/null) ]]; then
			echo "ERREUR : make relink."
			return 1
		fi
	fi
	return 0
}

function makefile_check_re
{
	execTimestamp=$(date -r "$dirToCheck"/"$execToCheck" 2> /dev/null)
	sleep 2 #pour etre certain que le nouvel executable a un nouveau timestamp.
	make re -C "$dirToCheck" &> /dev/null
	if [[ ! -f "$dirToCheck"/"$execToCheck" ]]; then
		echo "ERREUR : make re n'a pas cree l'executable."
		return 1
	fi
	if [[ "$execTimestamp" == $(date -r "$dirToCheck"/"$execToCheck" 2> /dev/null) ]]; then
		echo "ERREUR : make re n'a pas recompile l'executable."
		return 1
	fi
	return 0
}

function check_makefile
{
	echo -n "Makefile : "
	if [[ ! -f "$dirToCheck"/Makefile ]]; then
		echo "ERREUR : Makefile non trouve."
		return
	fi
	if ! makefile_check_clean; then
		return
	fi
	if ! makefile_check_fclean; then
		return
	fi
	if ! makefile_check_clean; then
		return
	fi
	if ! makefile_check_make false; then
		return
	fi
	if ! makefile_check_make true; then
		return
	fi
	if ! makefile_check_fclean; then
		return
	fi
	if ! makefile_check_re; then
		return
	fi
	if ! makefile_check_clean; then
		return
	fi
	if ! makefile_check_make false; then
		return
	fi
	if ! makefile_check_re; then
		return
	fi
	if ! makefile_check_make true; then
		return
	fi
	if ! makefile_check_clean; then
		return
	fi
	if ! makefile_check_re; then
		return
	fi
	echo "OK."
}

function check_forbidden_func
{
	echo -n "Fonctions interdites : "
	if [[ -z "$execToCheck" ]]; then
		echo "executable non initialise."
		return
	fi
	if [[ ! -f "$dirToCheck"/"$execToCheck" ]]; then
		echo "ERREUR : executable non trouve."
		return
	fi
	listOfFunctionInString=$(nm -u "$dirToCheck"/"$execToCheck" | grep "^_" | grep -v "^__" | cut -d_ -f2- | cut -d$ -f1)
	read -a listOfFunction <<< $listOfFunctionInString
	read -a listOfAuthorizedFunction <<< $authorizedFuncs
	for func in ${listOfFunction[@]}; do
		if [[ ! " ${listOfAuthorizedFunction[@]} " =~ " $func " ]]; then
			echo "ERREUR : la fonction $func n'est pas autorisee."
			return
		fi
	done
	echo "OK."
}

argv=("$@")
argc="$#"
idx="0"

while [[ "$idx" != "$argc" ]]; do
	param="${argv[$idx]}"
	if [[ "$param" =~ ^-.* ]]; then
		if [[ "$param" == "--help" ]] || [[ "$param" == "-h" ]]; then
			print_help
			exit 0
		elif [[ "$param" == "--authors" ]] || [[ "$param" == "-a" ]]; then
			(( ++idx ))
			param="${argv[$idx]}"
			if [[ -z "$param" ]]; then
				echo "Erreur : le parametre auteurs ne doit pas etre vide."
				exit 0
			else
				if [[ "$param" =~ \  ]]; then
					echo "Erreur : le parametre auteurs ne peut pas contenir d'espaces."
					exit 0
				else
					authors="$param"
				fi
			fi
		elif [[ "$param" == "--exec" ]] || [[ "$param" == "-e" ]]; then
			(( ++idx ))
			param="${argv[$idx]}"
			if [[ -z "$param" ]]; then
				echo "Erreur : le parametre executable ne doit pas etre vide."
				exit 0
			else
				execToCheck="$param"
			fi
		elif [[ "$param" == "--funcs" ]] || [[ "$param" == "-f" ]]; then
			(( ++idx ))
			param="${argv[$idx]}"
			if [[ -z "$param" ]]; then
				echo "Erreur : le parametre fonctions ne doit pas etre vide."
				exit 0
			else
				authorizedFuncs="$param"
			fi
		elif [[ "$param" == "--noauthorfile" ]]; then
			checkAuthorFile="false"
		elif [[ "$param" == "--nonorm" ]]; then
			checkNorm="false"
		elif [[ "$param" == "--nocodeauthors" ]]; then
			checkCodeAuthors="false"
		elif [[ "$param" == "--nomakefile" ]]; then
			checkMakefile="false"
		elif [[ "$param" == "--noforbidfunc" ]]; then
			checkForbidFunc="false"
		else
			echo "Erreur : parametre $param inconnu. Utilisez --help pour afficher l'aide."
			exit 0
		fi
	else
		if [[ "$dirToCheckIsCustom" == "false" ]]; then
			dirToCheck="$param"
			dirToCheckIsCustom="true"
		else
			echo "Trop d'arguments, le dossier du projet ne peut etre initialise qu'une fois. Utilisez --help pour afficher l'aide."
			exit 0
		fi
	fi
	(( ++idx ))
done

if [[ "$checkAuthorFile" == "true" ]]; then
	check_author_file
fi
if [[ "$checkNorm" == "true" ]]; then
	check_norme
fi
if [[ "$checkCodeAuthors" == "true" ]]; then
	check_author_of_code
fi
if [[ "$checkMakefile" == "true" ]]; then
	check_makefile
fi
if [[ "$checkForbidFunc" == "true" ]]; then
	make -C "$dirToCheck" &> /dev/null
	check_forbidden_func
fi
