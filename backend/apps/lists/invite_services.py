"""Pending list invites for emails that are not yet registered (FR-3.1)."""
from django.conf import settings
from django.core.mail import send_mail

from .models import (
    ListActivity,
    ListActivityAction,
    ListCollaborator,
    ListInvite,
)
from .realtime import broadcast_list_event
from .serializers import ListCollaboratorSerializer


def normalize_email(email: str) -> str:
    return email.strip().lower()


def send_list_invite_email(*, invite: ListInvite) -> None:
    """Best-effort notification; never fails the invite API."""
    inviter = invite.invited_by.email if invite.invited_by_id else "Someone"
    title = invite.list.title
    subject = f"You're invited to a Shoppa list: {title}"
    body = (
        f"{inviter} shared the shopping list \"{title}\" with you on Shoppa.\n\n"
        f"Create a free account using {invite.email} to open the list "
        f"({invite.permission} access).\n"
    )
    try:
        send_mail(
            subject,
            body,
            getattr(settings, "DEFAULT_FROM_EMAIL", "noreply@shoppa.app"),
            [invite.email],
            fail_silently=True,
        )
    except Exception:
        # Console/SMTP misconfig must not break sharing.
        pass


def create_or_update_invite(*, list_obj, email: str, permission: str, invited_by):
    """Create or refresh a pending invite. Returns (invite, created)."""
    email = normalize_email(email)
    invite, created = ListInvite.objects.update_or_create(
        list=list_obj,
        email=email,
        defaults={
            "permission": permission,
            "invited_by": invited_by,
        },
    )
    if created:
        ListActivity.objects.create(
            list=list_obj,
            actor=invited_by,
            action=ListActivityAction.COLLABORATOR_JOINED,
            detail=f"{email} invited (pending signup) as {permission}",
        )
    send_list_invite_email(invite=invite)
    return invite, created


def accept_pending_invites(user) -> int:
    """Turn pending invites for this email into collaborators. Returns count."""
    invites = list(
        ListInvite.objects.filter(email__iexact=normalize_email(user.email))
        .select_related("list", "invited_by")
    )
    accepted = 0
    for invite in invites:
        if invite.list.owner_id == user.id:
            invite.delete()
            continue
        collaborator, created = ListCollaborator.objects.get_or_create(
            list=invite.list,
            user=user,
            defaults={"permission": invite.permission},
        )
        if created:
            ListActivity.objects.create(
                list=invite.list,
                actor=invite.invited_by,
                action=ListActivityAction.COLLABORATOR_JOINED,
                detail=f"{user.email} joined via invite as {invite.permission}",
            )
            broadcast_list_event(
                invite.list_id,
                "collaborator.joined",
                ListCollaboratorSerializer(collaborator).data,
            )
            accepted += 1
        invite.delete()
    return accepted
